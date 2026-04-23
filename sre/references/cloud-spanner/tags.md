# Transaction Tag / Request Tag

Spanner のタグ機能を使うと、クエリやトランザクションを `SPANNER_SYS` 系ビューでサービス・ルート単位に絞り込める。**本番クリティカルパスでは必須**。

## 種類

| タグ | 付与対象 | ビュー |
|------|----------|--------|
| **Transaction Tag** | RW トランザクション全体 | `SPANNER_SYS.TXN_STATS_*`, `SPANNER_SYS.LOCK_STATS_*` |
| **Request Tag** | 単一クエリ / リクエスト | `SPANNER_SYS.QUERY_STATS_*`, `SPANNER_SYS.READ_STATS_*` |

## ColorSing の命名規約

形式: `service=<service>,route=<HTTP_METHOD>_<path>`

**例**:

- `service=api,route=POST_/live/comment`
- `service=api,route=GET_/user/:id/profile`
- `service=worker,route=coin_batch_aggregation`
- `service=cron,route=daily_ranking`

**ルール**:

- カンマ区切りで `key=value` を並べる（タグは単一文字列なので区切りを工夫）
- パスパラメータは `:` 付きにする（`/user/:id`）
- 集計しやすくするため、パスに動的値を含めない

## Go コード例

### 公式 SDK

```go
import "cloud.google.com/go/spanner"

// Transaction Tag
_, err := client.ReadWriteTransactionWithOptions(ctx,
    func(ctx context.Context, txn *spanner.ReadWriteTransaction) error {
        // Request Tag を個別クエリに
        iter := txn.QueryWithOptions(ctx, stmt, spanner.QueryOptions{
            RequestTag: "service=api,route=POST_/live/comment,op=read_live",
        })
        // ...
        return nil
    },
    spanner.TransactionOptions{
        TransactionTag: "service=api,route=POST_/live/comment",
    })
```

### ColorSing 内製ラッパー

```go
// ※ i.db, transactable.Transaction, BeginRwTransactionWithTag は
//   ColorSing 内製ラッパー（公式 cloud.google.com/go/spanner API ではない）

err := i.db.BeginRwTransactionWithTag(ctx,
    "service=api,route=POST_/live/comment",
    func(ctx context.Context, txn transactable.Transaction) error {
        // ...
    })
```

**付与対象**:

- [ ] すべての RW トランザクション（本番クリティカルパス）
- [ ] 重いバッチクエリ
- [ ] ユーザー報告された遅延クエリを再現する際のデバッグ用クエリ

## SPANNER_SYS での絞り込み

### TXN_STATS（トランザクション統計）

```sql
-- 直近 1 時間で特定ルートの平均レイテンシ
SELECT
  transaction_tag,
  AVG(avg_total_latency_seconds) AS avg_latency,
  SUM(count) AS total_count,
  SUM(commit_abort_count) AS abort_count
FROM SPANNER_SYS.TXN_STATS_TOP_HOUR
WHERE transaction_tag LIKE 'service=api,route=POST_/live/comment%'
  AND interval_end >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
GROUP BY transaction_tag
ORDER BY avg_latency DESC;
```

### QUERY_STATS（クエリ統計）

```sql
-- Request Tag ごとの CPU 消費
SELECT
  request_tag,
  SUM(execution_count) AS exec_count,
  AVG(avg_cpu_seconds) AS avg_cpu
FROM SPANNER_SYS.QUERY_STATS_TOP_HOUR
WHERE request_tag != ''
  AND interval_end >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
GROUP BY request_tag
ORDER BY avg_cpu DESC
LIMIT 20;
```

### LOCK_STATS（ロック競合）

```sql
-- ロック待ち時間が長いトランザクション
SELECT
  row_range_start_key,
  lock_wait_seconds,
  sample_lock_requests
FROM SPANNER_SYS.LOCK_STATS_TOP_HOUR
WHERE interval_end >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
ORDER BY lock_wait_seconds DESC
LIMIT 20;
```

`sample_lock_requests` に `transaction_tag` が含まれるのでロック競合の犯人特定ができる。

## PR レビュー観点

- [ ] 新規 RW トランザクションに Transaction Tag が付いているか
- [ ] 新規重いクエリに Request Tag が付いているか
- [ ] 命名規約に従っているか（`service=..., route=...`）
- [ ] パスパラメータが動的値ではなく `:id` などプレースホルダ形式か

## 参考

- [リクエスト タグとトランザクション タグ | Spanner](https://cloud.google.com/spanner/docs/introspection/troubleshooting-with-tags)
