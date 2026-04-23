# Stale Read の使い分け

Cloud Spanner の読み取りには 3 種類ある。クリティカルパス以外では積極的に Stale Read を使うことでリーダーレプリカの負荷を下げ、レイテンシも改善できる。

## 3 種類の読み取り

| 種類 | 特徴 | レプリカ |
|------|------|----------|
| **Strong Read** | 常に最新データを返す（クエリ開始時点のコミット済みデータ） | リーダーレプリカのみ |
| **Bounded Staleness** | 指定した時間以内の古さを許容（例: 10 秒以内） | ローカルレプリカから読める可能性あり |
| **Exact Staleness** | 正確に N 秒前の断面を読む（タイムスタンプ指定も可） | ローカルレプリカから読める可能性あり |

Stale Read（Bounded / Exact）はリーダー以外のレプリカから読めるため、リーダー CPU 使用率の低減とレイテンシ改善の両方に効く。

## ColorSing での使い分け

| ユースケース | 読み取り方式 | 備考 |
|--------------|--------------|------|
| 決済・コイン残高（`UserCoinBalances`）・ダイヤモンド残高（`UserDiamondBalances`）・換金処理 | **Strong Read 必須** | 金銭が絡むので古いデータ絶対 NG |
| 認証・権限チェック（BAN 判定など） | **Strong Read 必須** | 直前の BAN 反映漏れ防止 |
| プロフィール参照、フォロワー一覧、ランキング表示、ホームフィード | **Exact Staleness 15〜30 秒** | ユーザー体感として問題ない範囲 |
| 運用ダッシュボード・分析クエリ | **Exact Staleness 60 秒以上** | 集計クエリはリーダー負荷を避ける |
| サムネイル・配信一覧のキャッシュ更新 | **Exact Staleness 30 秒** | CDN / 内部キャッシュ前提 |

## Go コード例

### ColorSing 内製ラッパー

```go
// ※ i.db, transactable.Transaction, BeginRoTransactionWithStaleness は
//   ColorSing 内製ラッパー（公式 cloud.google.com/go/spanner API ではない）

// Exact Staleness 15 秒
err := i.db.BeginRoTransactionWithStaleness(ctx, 15*time.Second,
    func(ctx context.Context, txn transactable.Transaction) error {
        profile, err = i.userRepository.Find(ctx, txn, userID)
        return err
    })
```

### 公式 SDK

```go
import "cloud.google.com/go/spanner"

// Exact Staleness
txn := client.ReadOnlyTransaction().
    WithTimestampBound(spanner.ExactStaleness(15 * time.Second))
defer txn.Close()

iter := txn.Query(ctx, spanner.Statement{SQL: "SELECT ..."})
// ...

// Bounded Staleness（最大 10 秒まで古くてよい）
txn := client.ReadOnlyTransaction().
    WithTimestampBound(spanner.MaxStaleness(10 * time.Second))
```

## PR レビュー観点

- [ ] **残高・決済・権限** のクエリが Stale Read になっていないか
- [ ] Stale Read を使うときに何秒古くて良いかが PR 説明 or コメントに書かれているか
- [ ] Strong Read から Stale Read に変えた場合、影響範囲（キャッシュ、UI 挙動）が確認されているか
- [ ] Exact Staleness の値が妥当か（30 秒以下推奨、60 秒超はダッシュボード限定）

## 参考

- [Spanner の読み取りタイプ | Google Cloud](https://cloud.google.com/spanner/docs/reads)
