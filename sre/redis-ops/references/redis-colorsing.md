# ColorSing 固有の Redis 運用知識

## 1. ColorSing における Redis の重要性

ColorSing において Redis は**単なるキャッシュストアではなく、ランキングデータ等を格納する超重要なデータベース**。

### データ分類

| 種類 | 例 | 消失時の影響 |
|------|-----|------------|
| キャッシュ系 | セッション情報、一時キャッシュ (LiverLeagues, Lives) | なし（再計算・再取得可） |
| 永続性が必要 | パール杯ランキング等 | 影響大（サービス停止） |

### メモリ使用状況（2025年夏時点）
- 容量: 18GB / 25GB（限界間近）
- キャッシュ用途（LiverLeagues, Lives）は合計数MB程度で分離しても延命効果小

---

## 2. Spanner - Redis 整合性問題

Spanner トランザクション内で Redis を更新すると、Spanner ロールバック時に Redis だけデータが残る不整合が発生する。

### 対策パターン

| 対策 | 例 |
|------|-----|
| 自動リカバリ | 不整合修正バッチを定期実行 |
| 手動リカバリ | 開発者がバッチで修正 |
| 影響緩和 | Spanner とズレてもユーザー不利益が出ない設計 |
| 検知 | 不整合検知で Slack アラート |

### 設計原則
- 新規機能は設計段階で「Redis のデータが消えたらどうなるか」を評価
- 影響大なら Spanner の正本データから Redis を再生成するリビルドコマンドを用意
- AOF は「最後の砦」で、リプレイに数日かかる可能性あり

---

## 3. Gob シリアライズの互換性

ColorSing では Go のモデルを **gob 形式** で Redis に保存している。

### 注意点
- gob モデルに変更を加えると、既存データのデシリアライズでエラーが発生
- キャッシュ用途なので、デシリアライズ失敗時はオリジン（Spanner 等）からデータ取得で継続

### 実装ガイドライン
```go
// gob 読み出しでデシリアライズに失敗しても API 処理を継続する
data, err := redis.Get(ctx, key)
if err != nil {
    // キャッシュミスまたはエラー → オリジンから取得
    return fetchFromSpanner(ctx, id)
}

var model MyModel
if err := gob.NewDecoder(bytes.NewReader(data)).Decode(&model); err != nil {
    // デシリアライズ失敗 → オリジンから取得
    log.Warn("gob decode failed, falling back to origin", "key", key, "err", err)
    return fetchFromSpanner(ctx, id)
}
return &model, nil
```

---

## 4. HEXPIRE の利用方針

### 技術的背景
- Redis 7.4 から Hash フィールド単位で HEXPIRE による TTL 設定が可能
- miniredis / redismock は HEXPIRE 未対応 → ユニットテストには実機 Redis が必要
- 実機テストでは `time.Sleep` 等による実時間経過が必要

### チーム決定（2025-06-05 tech チーム定例）

**当面 HEXPIRE 利用は消極的とする。理由:**
1. HEXPIRE 自体が新しく十分に枯れていない
2. BigKey 気味の場合のパフォーマンス事例が見当たらない
3. Valkey 移管の可能性を考慮した互換性の不安
4. 現時点では他の解決策で対応可能

**方針:** Redis v8（オープンソースライセンス復帰予定）まで特別な理由がない限り利用を控える。

---

## 5. Redis Cluster 移行プロジェクト

### 背景
- メモリ 18GB/25GB で限界間近（2025-07-01 時点で 80% 超）
- Redis Cloud では 25GB 超はクラスタ化が必要

### 方式比較結論

| 方式 | 結論 |
|------|------|
| Redis Cluster | 長期的に運用コスト低だが移行コスト大 |
| Redis Ring | Cluster と同等だが自動再配置不可。あえて使う理由なし |
| 垂直分割 | 移行コスト低（18人日）だが再膨張時に再分割必要 |

### go-redis Cluster Client 設定例

```go
rdb := redis.NewClusterClient(&redis.ClusterOptions{
    Addrs:          []string{"Redis ClusterのFQDN:ポート"},
    Username:       "default",
    Password:       "パスワード",
    RouteByLatency: true,  // レイテンシの小さいノードを選択
    PoolSize:       100,   // ノードごとのコネクション上限
})
```

### CROSSSLOT 対応移行プラン

#### ステップ
1. Hash Tag 付きキーで GET → なければ Hash Tag なしキーで GET する実装をリリース
2. Hash Tag 付きキーで更新する実装をリリース（裏で RENAME ジョブ実行）
3. 全キー RENAME 完了後、Hash Tag なしキーの参照を削除
4. Redis Cluster 新設 → Active-Passive で同期
5. 配信時間外（1:00〜1:30）にアプリ接続先を切替

#### go-redis の自動再送
- `-MOVED` と `-ASK` リダイレクトを自動再送しスロットマップも更新
- 非クロススロット系コマンドは変更不要

---

## 6. CROSSSLOT キー一覧

### MGET 対象（Pipeline 単発 GET に分解可能）

| カテゴリ | キーパターン | 工数見積 |
|---------|------------|---------|
| ライブ統計 | `live_stat:liver:all:{liverUserID}:{statsType}` 等 | コーディング 2人日 + dev確認 1人日 |
| 初馴染み・初+ | `is_hatsunajimi_or_first_look:{listenerID}:{liverID}:{date}` 等 | コーディング 2人日 + dev確認 1人日 |
| 推しPt | `liver_monthly_fave_pt:{liverID}:{YYYY-MM}` 等 | コーディング 1人日 + dev確認 1人日 |
| 昇格戦メーター | `liver_league_promotion_meter_score:*` 等 | コーディング 2人日 + dev確認 1人日 |
| 配信統計 | `liver_30_minutes_live_days_at_daily_first_live:{liverUserID}` | コーディング 2人日 + dev確認 1人日 |
| ダイヤ獲得系 | `pf_received_*_coin_amount:{date}` 等 | コーディング 3人日 + dev確認 1人日 |

### EVALSHA 対象
- ダイヤ獲得系の各種 coin_amount キー（liver/pf）

### ZUNIONSTORE 対象
- 昇格戦メーター（コーディング 5人日 + dev確認 1人日）

### 工数概算
- 全体: 約 50 キー x 3人日 = 150人日
- QA チームによるフルリグレッションテストも必要

---

## 7. 新規 Key 設計チェックリスト

新しい Key パターンを追加する際の確認事項:

- [ ] 合計容量は 10MB 以下か？（最大でも 100MB 以下。超える場合は tech チームに相談）
- [ ] Key 数の増加パターンは OK か？（ユーザー数 x ライブ数 = NG）
- [ ] Key の長さは 100 bytes 以下か？
- [ ] 値のサイズが時間経過で線形増加しないか？
- [ ] ビッグキーにならないか？
- [ ] TTL（Expire）を設定しているか？（キャッシュは必須）
- [ ] Gob でシリアライズする場合、デシリアライズ失敗時にオリジンから取得する設計か？
- [ ] データ消失時の復旧手段を検討したか？
- [ ] Spanner トランザクション内で Redis を更新する場合の整合性対策はあるか？
- [ ] Redis Cluster 移行後の CROSSSLOT 問題は考慮したか？
- [ ] Hash Tag を使う場合、カーディナリティは十分高いか？

---

## 8. TTL なし 2023 年キーの問題

RDB 分析で TTL が設定されていない 2023 年のキーが存在することが判明。これらは削除可能性が高いため、定期的にクリーンアップを検討すべき。

参照: Notion「TTLが設定されていない2023年のRedisキーprefix一覧」
