# Redis 運用ナレッジベース

## 1. コマンド安全性の詳細

### 時間計算量とブロッキング

Redis はシングルスレッドで動作し、あるコマンドの実行中は他のすべてのコマンドをブロックする。公式ドキュメントでは各コマンドの時間計算量が明記されている。

#### 危険なコマンド一覧

| コマンド | 時間計算量 | リスク | 代替手段 |
|---------|-----------|--------|---------|
| KEYS | O(N) N=全キー数 | サービス停止 | SCAN |
| ZRANGEBYSCORE | O(log(N)+M) M=結果数 | 結果数が多いとブロック | Spanner/ElasticSearch |
| HGETALL | O(N) N=フィールド数 | Hash サイズ大でブロック | HSCAN, HGET |
| DEL (ビッグキー) | O(N) | メモリ解放でブロック | UNLINK (非同期削除) |

#### SCAN の安全な使い方

```shell
# 本番環境での SCAN: COUNT 100 + sleep で負荷分散
SCAN 0 COUNT 100
# → カーソルが 0 になるまで繰り返し
# → 各イテレーション間に sleep 0.1s を挟む
```

- `COUNT` はイテレーションごとの「大体の仕事量」を指定
- O(1) だが COUNT 10000 など大きな値は KEYS と同等の影響
- 新規で実装に追加する場合は tech チームに相談必須
- 手動作業では 100 件ずつを目処にする

### 範囲検索の代替

多数のキーを対象にした操作は Redis ではなく以下を使う:
- **Spanner**: 構造化データの範囲検索
- **ElasticSearch**: 全文検索、複雑なクエリ

---

## 2. Atomic 実行の詳細

### Transaction (MULTI/EXEC)

```shell
MULTI          # キューイング開始
INCR foo1
EXPIRE foo1 3600
EXEC           # キューの中身を連続実行
```

- クライアントコネクションごとにキューイング
- EXEC 時に一括実行（間に他コマンドが挟まらない）
- 中間データを使った条件分岐は不可
- Redis Cluster ではクロススロットな処理不可

### Lua Scripting (EVAL)

```shell
# 基本形
EVAL "return { redis.call('INCR', 'foo1'), redis.call('EXPIRE', 'foo1', 3600) }" 0

# 条件分岐の例: foo2 が偶数なら foo1 をインクリメント
EVAL "
local val = redis.call('GET', 'foo2')
if val then
  local num = tonumber(val)
  if num and num % 2 == 0 then
    return redis.call('INCR', 'foo1')
  end
end
return nil
" 0
```

- 内部で変数・if 文が使える
- Transaction でできないこともカバー可能
- **ほぼすべてのケースで Lua Scripting を推奨**

### WATCH + MULTI/EXEC（楽観ロック）

```
loop:
  WATCH foo2                          # 楽観ロック取得
  foo2 = redis.get("foo2")
  bar1 = spanner("SELECT bar1 FROM...")  # 外部DB参照
  
  if foo2 % bar1 == 0:
    redis.multi()
    redis.incr("foo2")
    result = redis.exec()
    if result is nil:                 # foo2 が更新されていたら EXEC 失敗
      continue loop                   # リトライ
    else:
      break
  else:
    UNWATCH
    break
```

- Redis 以外の外部依存がある条件で使用
- 非常に複雑になりがちなので、このロジックが不要な設計を目指す

---

## 3. TTL (Time to Live) の詳細

### Key 単位の TTL

- TTL は原則 **Key 単位** で設定
- set/zset/hash 型でも Key 全体に対して TTL を設定
- 例外: Redis 7.4 以降は Hash フィールド単位で TTL 設定可能（HEXPIRE）

### TTL 設定方法

| コマンド | 説明 | 例 |
|---------|------|-----|
| `EXPIRE key seconds` | 期間で指定 | `EXPIRE foo 3600` (1時間) |
| `EXPIREAT key timestamp` | 日時で指定 | `EXPIREAT foo 1735689600` (2025/01/01) |

月間ランキングのような期間が明確なデータには日時指定が意図を表現しやすい。

### TTL オプション

| オプション | 動作 |
|-----------|------|
| NX | TTL が存在しない時のみ設定 |
| XX | TTL が存在する時のみ上書き |
| GT | 既存 TTL より新しい TTL が長い時のみ上書き |
| LT | 既存 TTL より新しい TTL が短い時のみ上書き |

### TTL と物理削除

- TTL を迎えた Key はクライアントから**即座に参照不可**
- ただし**物理削除は非同期**
- 最大で `maxmemory` の 20% 程度が期限切れデータとして残存

---

## 4. Redis Cluster のシャーディング

### 基本メカニズム

```
SET foo1 bar1 --> CRC16(foo1) mod 16384 --> slot X --> master001
SET foo2 bar2 --> CRC16(foo2) mod 16384 --> slot Y --> master002
```

- 全体で 16384 スロット
- 各 master ノードが特定範囲のスロットを担当
- Key の CRC16 ハッシュ値でスロットを算出

### クロススロット制約

```shell
# スタンドアロンでは OK だが Cluster では CROSSSLOT エラー
MGET foo1 foo2    # foo1 と foo2 が異なるスロットの場合エラー
```

### Hash Tag によるスロット制御

```shell
# {foo} 内の文字列でハッシュ計算 → 同一スロットに配置
SET {foo}1 bar1 --> CRC16(foo) --> slot Z --> master003
SET {foo}2 bar2 --> CRC16(foo) --> slot Z --> master003

# 同一スロットなので MGET 可能
MGET {foo}1 {foo}2
```

### Hash Tag のホットスポット問題

Hash Tag を使うと特定スロットにデータが偏り、Cluster のシャーディングが機能しなくなる。

**対策:**
- カーディナリティの高い値（例: user ID）を Hash Tag に使用
- `{userid}` とすることでユーザーごとにノードが分散

### Hash Tag による障害影響範囲の制御

| 設計 | 障害影響 |
|------|---------|
| Hash Tag なし（ランダム分散） | 全ユーザーに影響 |
| `{userid}` で局所化 | 障害ノードのユーザーのみ影響 |

恩恵を最大化するにはサービス全体の Redis Key 設計が必要。

### 単一 Key ホットスポットの対策

例: `maintenance` キーに全アプリがアクセスする場合

1. **インメモリキャッシュ**: アプリ側で 10 秒程度キャッシュ
2. **Key 分散**: `maintenance1`, `maintenance2`, `maintenance3` に同じ値を書き、ランダムアクセス

---

## 5. Key 設計ベストプラクティス

### Key の長さ

```shell
# 問題ないがもっと短縮したい
cache:userinfo:{1111}
# 推奨
c:ui:{1111}
```

- 目標: 100 bytes 程度
- 上限: 1KB 以下
- Key 長はメモリ消費と処理性能の両方にオーバーヘッド

### Value のシリアライズ

| 方式 | 特徴 |
|------|------|
| msgpack | 高効率、多言語対応 |
| protobuf | スキーマ付き、高効率 |
| JSON | 人間可読だがサイズ大 |
| gzip 圧縮 | 自然言語が多い場合に有効（CPU コストとのトレードオフ） |

### 内部エンコーディングの活用

Redis は条件を満たすと圧縮効率の良いエンコーディングを適用:
- 整数のみの SET 型
- 要素数が少なく文字列長が一定以下の ZSET 型

キーを上手く分割してこの範囲に収まるようにすると容量効率が大幅に改善。

### 7.4 の Hash フィールド TTL 活用

Redis 7.4 からは Hash フィールド単位で TTL 設定可能。TTL を分けるために Key を分割していたものを Hash 型に統合すれば:
- メモリ効率改善（内部エンコーディングの恩恵）
- ただしホットスポット問題とのトレードオフ

---

## 6. メモリ管理

### Eviction Policy

| ポリシー | 対象 | アルゴリズム | 説明 |
|---------|------|------------|------|
| noeviction | - | なし | 追い出しなし（現在の設定） |
| allkeys-lru | 全 Key | LRU | アクセス頻度低を追い出し |
| allkeys-lfu | 全 Key | LFU | ヒット率低を追い出し |
| volatile-lru | TTL 付き | LRU | Redis デフォルト |
| volatile-lfu | TTL 付き | LFU | - |
| volatile-random | TTL 付き | ランダム | - |
| volatile-ttl | TTL 付き | TTL 近い順 | - |

- LFU はメモリオーバーヘッドが LRU より高い
- 一般的には LRU で十分な精度

### データ保護

#### レプリケーション

```shell
SET foo "bar"
WAIT 1 1000    # 最低 1 レプリカに到達するまで最大 1 秒待つ
```

- Redis のレプリケーションは**完全非同期**
- 書き込み直後のダウンでデータロスト
- `WAIT` で保証可能だがパフォーマンス低下
- ほとんどのケースで WAIT を使うなら他の DB を選ぶべき

#### ファイル永続化

- fsync は基本非同期
- 同期設定はインメモリ DB の最大の利点を犠牲にする
- AOF リプレイに数日かかるケースもある

---

## 7. RDB 分析手法

### 使用ツール

| ツール | 用途 |
|--------|------|
| [rdb](https://github.com/HDT3213/rdb) | RDB ファイルを CSV に変換 |
| [Miller](https://miller.readthedocs.io/) | CSV パース & 集約 |

### 分析スクリプト

```shell
# RDB ファイルを展開・CSV 変換
gunzip backup.rdb.gz
rdb -c memory -o mem.csv backup.rdb

# 最小カラムに絞る
mlr --csv cut -f key,size,expiration mem.csv > step1_min.csv

# グルーピング: TTL なし+2023キー / TTL なし+その他 / プレフィックス別
mlr --csv put '
  $key = ($expiration == "" && $key =~ "2023")
    ? "no_expire_2023"
    : ($expiration == ""
        ? "no_expire_others"
        : sub($key, ":.*", "")
      )
' step1_min.csv > step2_grouped.csv

# 集約・ソート
mlr --csv \
  stats1 -a sum -f size -g key \
  then rename size_sum,total_size \
  then sort -nr total_size \
  step2_grouped.csv > grouped_mem.csv
```
