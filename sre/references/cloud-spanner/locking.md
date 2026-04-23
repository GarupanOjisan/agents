# ロックの挙動について

Spanner のロックの挙動を把握しておくことで、思わぬパフォーマンス悪化を避けることができる。

## 基本の挙動

Spanner のロックは**楽観ロック方式**を基本とする。同じキーに同時刻にアクセスしそうなケースでは挙動を意識する。

### 競合時の優先度

ロックが競合した場合、優先度によって片方が待機（wait）するか、中断（abort）させてロックを奪う。優先度は以下のように決まる:

- トランザクションの最初のオペレーションが早い方が高い
- 一度リトライされたトランザクションは優先度が上がる
- 明示的に指定することも可能（`PRIORITY_HIGH/MEDIUM/LOW`）

### 共有ロック（RW の SELECT）

RW トランザクション内で `SELECT` したレコードは**共有ロック**が取られる。共有ロックの範囲が広いほど他トランザクションが abort しやすくなるため、RW のスコープを最小化し、書き込みに本当に必要なキーのみを読むようにする。

読み取りのみなら [RO トランザクションを優先](./implementation-minimum-rules.md) する。

### 競合時のリトライと副作用

abort されたトランザクションは各言語のライブラリによって自動リトライされる。トランザクションの外の `slice` に `append` するような処理が意図せずリトライされて二重実行される点に注意する。副作用は `AfterCommit` フックかトランザクション外に出す。

## 悲観ロック（Redis ベース）

楽観ロックだと競合必至のキー（ライバー情報 / 配信情報など、多数のリスナーが同時アクセスする）では abort が多発するため、ColorSing では **Redis を使った悲観ロック**を実装している。

```go
// ※ i.db, transactable.Transaction, BeginRwTransactionWithUserLock は
//   ColorSing 内製ラッパー（公式 cloud.google.com/go/spanner API ではない）
err = i.db.BeginRwTransactionWithUserLock(ctx, i.redisClient, liverUserID,
    func(ctx context.Context, txn transactable.Transaction) error {
        // 同じ liverUserID のトランザクションは直列化される
    })
```

詳細は [Spanner で最低限実装で気をつけること](./implementation-minimum-rules.md) の「必要に応じて悲観ロックを取る」を参照。

## Redis 悲観ロックの運用上の落とし穴

Redis ベースの悲観ロックは楽観ロック abort の多発を抑えられる強力な手段だが、運用上の注意点が多い。以下は**必ず守る**。

### 1. Redis 障害時の方針

Redis（Memorystore）が落ちたときに以下のどちらを取るか事前に決めておく:

| 方針 | 動作 | メリット | デメリット |
|------|------|----------|------------|
| **fail-closed** | ロック取得失敗で書き込み停止 | データ整合性を最優先 | Redis 障害 = サービス障害 |
| **fail-open** | ロックをスキップして楽観ロックにフォールバック | 可用性を優先 | abort 多発 / 整合性リスク |

**ColorSing の現状方針**: **fail-closed**（残高・配信など整合性クリティカルな用途が多いため）。Redis 障害時は該当エンドポイントが 5xx を返すのを許容。ただしキャッシュ用途と悲観ロック用途は可能なら Redis インスタンスを分ける。

### 2. Spanner TX abort → 自動リトライ時のロック挙動

Spanner の RW TX は Spanner 起因で abort されて**同一セッション内で自動リトライ**されることがある。このとき:

- Redis のロックは**リトライをまたいで保持されたまま**（通常のラッパー実装はそう）
- ロック取得は TX 開始前に 1 回だけ行い、TX 終了時（成功 / 失敗）に 1 回 unlock する
- Spanner 側のリトライ 1 回ごとに Redis を再取得してはいけない（自分自身とデッドロック）

**TTL との関係**: Spanner リトライも含めて TX が長引く可能性があるため、TTL は**十分長めに**設定する（次項）。

### 3. TTL 設計

- Spanner TX の最大実行時間は commit wait 含めて数十秒〜（デフォルト上限 60 秒 + リトライ）
- Redis ロックの TTL は **60〜120 秒以上**を推奨
- 短すぎる TTL は TX 実行中にロックが勝手に切れて、他 TX が割り込む危険
- 長すぎる TTL は unlock 忘れ時の回復が遅くなる

**目安**: 120 秒（Spanner TX 最大時間の 2 倍程度）

### 4. context キャンセル / panic 時のロック解放

```go
func doWithLock(ctx context.Context, key string) error {
    if err := redisLock.Lock(ctx, key); err != nil {
        return err
    }
    defer redisLock.Unlock(ctx, key)  // 必須

    // ... Spanner TX ...
    return nil
}
```

- `defer unlock` を**必ず**書く
- unlock を忘れると TTL 切れまで他 TX が全部ブロックされる（= 障害）
- panic でも `defer` は走るので OK

### 5. ロック取得順序（デッドロック回避）

複数ユーザーのロックを同時に取る場合（例: 送金で送信者 + 受信者）:

```go
// NG: 取得順がバラバラだとデッドロック
redisLock.Lock(ctx, senderID)
redisLock.Lock(ctx, receiverID)

// OK: 必ずソートしてから取得
ids := []string{senderID, receiverID}
sort.Strings(ids)
for _, id := range ids {
    redisLock.Lock(ctx, id)
}
```

**ルール**: 複数キーをロックするときは必ず**ユーザー ID 昇順**など決まった順序で取得する。

### 6. Redlock vs 単一 Redis

ColorSing は **単一 Redis（Memorystore）前提**。

- Redlock（複数 Redis 投票）は使っていない
- フェイルオーバー中の split-brain による重複ロックリスクは**許容する**（頻度が低く、Spanner 側の楽観ロックで最終防衛できるため）
- より強い保証が必要なら Spanner ネイティブロックヒントに移行を検討

### 7. Spanner ネイティブロックヒントを選ばなかった理由

Spanner には `@{LOCK_SCANNED_RANGES=exclusive}` というクエリヒントで排他ロックを取る機能がある。これを選ばなかった理由:

- ColorSing では**複数 DB（Spanner + Redis + MySQL）をまたぐ**排他制御が必要な場面があり、ロックの場所を Redis に寄せている方が運用しやすい
- **分散キー（ユーザー ID）単位で直列化**したいケースが多く、テーブル行単位のロックより粒度が適切
- Spanner ネイティブロックは TX 内でのみ有効で、ロックの有無を TX 外から観測しにくい
- Redis なら `EXISTS key` でロック状態を運用ツールから確認できる

### チェックリスト

- [ ] `defer unlock` が書かれている
- [ ] TTL が 60 秒以上（Spanner TX 時間 + 余裕）
- [ ] 複数キーロック時は順序が決まっている
- [ ] Redis 障害時の挙動（fail-closed / fail-open）を実装者が理解している
- [ ] ロックキーの命名規約が統一されている（例: `lock:user:<userID>`）
