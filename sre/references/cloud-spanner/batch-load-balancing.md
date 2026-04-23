# バッチ処理の負荷分散

全ユーザーのデータを集計・加工するようなバッチを作成する際のノウハウ。

## PK を分割して並列実行する

全ユーザーが処理対象の場合、例えば **UUIDv4 の PK の先頭 1 桁**を元に 16 分割することで 16 並列で実行できる。

**注意点**: 並列実行するプロセスがお互いに競合を起こさないかどうかは、**設計の段階で必ず明らかにする**こと。書き込み対象のキー空間が重複しなければ競合は発生しない。

## 実装の目安

- PK 先頭 1 桁で 16 分割 → `[0-9a-f]` の 16 並列
- 各ワーカーは自分のシャード範囲のみをスキャン / 更新
- ホットスポットを避けるため、単一ワーカーが単調にキーを処理する設計にしない

## PRIORITY_LOW を付ける

バッチ処理は本番トラフィックと CPU を奪い合う。**バッチ側は必ず `PRIORITY_LOW`** を付けてリアルタイム処理を優先する。

```go
import "cloud.google.com/go/spanner"
import sppb "cloud.google.com/go/spanner/apiv1/spannerpb"

iter := client.Single().QueryWithOptions(ctx, stmt, spanner.QueryOptions{
    Priority: sppb.RequestOptions_PRIORITY_LOW,
    RequestTag: "service=batch,route=daily_coin_aggregation",
})
```

RW TX でも同様:

```go
_, err := client.ReadWriteTransactionWithOptions(ctx, fn,
    spanner.TransactionOptions{
        CommitPriority: sppb.RequestOptions_PRIORITY_LOW,
        TransactionTag: "service=batch,route=daily_coin_aggregation",
    })
```

## Partitioned Query / PartitionRead API

大量スキャンは `BatchReadOnlyTransaction` + `PartitionQuery` / `PartitionRead` で Spanner 側に分割してもらう選択肢もある。

**使う判断**:

- スキャン対象が**数千万行以上**
- 分割後に並列ワーカー（Dataflow や自前 Go goroutine）で処理
- **PK 先頭分割が難しい**場合（UUIDv4 以外の PK を使っているテーブル）

```go
tx, _ := client.BatchReadOnlyTransaction(ctx, spanner.StrongRead())
defer tx.Close()

partitions, _ := tx.PartitionQuery(ctx, stmt, spanner.PartitionOptions{
    MaxPartitions: 16,
})
// 各 partition を別ワーカーで処理
for _, p := range partitions {
    go func(p *spanner.Partition) {
        iter := tx.Execute(ctx, p)
        // ...
    }(p)
}
```

## 冪等性と checkpoint テーブル

バッチは途中失敗しうる。**冪等に書く** + **checkpoint テーブルで再開点を管理**する。

```sql
CREATE TABLE BatchCheckpoints (
  BatchId      STRING(64) NOT NULL,
  ShardKey     STRING(8) NOT NULL,
  LastPK       STRING(36),
  ProcessedAt  TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
  Status       STRING(32) NOT NULL,
) PRIMARY KEY (BatchId, ShardKey);
```

- 各シャードワーカーが最後に処理した PK を記録
- 再実行時は `LastPK` から再開
- ステータス `running` / `done` / `failed` を管理

## 途中失敗時の再開点管理

- **冪等な更新**（`Balance = Balance + X` のような累積は NG。`Status = 'done'` のような上書きは OK）を前提とする
- 累積更新が必要なら別途処理済みフラグテーブルを用意
- checkpoint 書き込みはメインのトランザクションと**同一 TX** で行う（部分進行の不整合回避）

## Autoscaler との相互作用

Spanner は Autoscaler が動いているが、バッチ開始直後は CPU 急上昇でスケールアウトが間に合わないことがある。

**対策**:

- [Spanner のオートスケーリング](./autoscaling.md) のスケジュール機能で**バッチ開始の 10 分前から min ノード数を上げる**
- Cloud Scheduler + Terraform で自動化
- バッチ終了後も 10 分は高い min を維持（スケールダウンのため）

**例**（日次バッチが 03:00 開始の場合）:

- 02:50 に min を +50% に引き上げ
- 04:00 にバッチ完了想定、04:30 に min を元に戻す
