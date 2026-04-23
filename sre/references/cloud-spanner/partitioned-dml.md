# Partitioned DML

大量行の UPDATE / DELETE では **Partitioned DML** を使う。通常 DML は 1 トランザクションあたり **80,000 ミューテーション**の制限があるため、数万行を超える更新はすぐに上限に達する。

## 使うべき場面

- 古いデータのアーカイブ / 削除（TTL でカバーしきれない業務要件の削除）
- 一括ステータス変更（例: 特定キャンペーン対象ユーザーのフラグ更新）
- マイグレーション時のバックフィル
- **更新行数が数万行を超える見込みなら Partitioned DML を選ぶ**

## 制約（重要）

- **冪等性が必須**: Partitioned DML は内部的に複数パーティションで分割実行され、部分的にリトライされる可能性がある。同じ行が複数回 UPDATE されても結果が同じになる文を書く
- **1 パーティションあたり 80,000 ミューテーション上限**: パーティション境界を跨ぐ更新は自動分割されるが、1 パーティションに収まらない大量更新（同一 PK 先頭への集中）は失敗する
- **同時実行数の制約**: 同一データベースで同時実行できる Partitioned DML は制限あり（通常 DML と干渉するため）
- **インターリーブ子の扱い**: 親を DELETE する場合、先に子テーブルを Partitioned DML で削除してから親を削除する（ON DELETE CASCADE は Partitioned DML では使えない）
- **アトミックではない**: 途中まで実行された状態が見える時間がある
- **JOIN / サブクエリに制限**: 相関サブクエリや一部の式が使えない

## 冪等な DML の例

```sql
-- OK: 冪等（何度実行しても結果同じ）
UPDATE Users SET Status = 'inactive' WHERE LastLoginAt < '2024-01-01';

-- OK: 冪等（削除は何度やっても同じ）
DELETE FROM SessionTokens WHERE ExpiresAt < CURRENT_TIMESTAMP();
```

## 非冪等な DML の例（Partitioned DML では絶対に使うな）

```sql
-- NG: 非冪等（リトライで二重加算される）
UPDATE UserCoinBalances SET Balance = Balance + 100 WHERE UserId IN (...);

-- NG: 非冪等（CURRENT_TIMESTAMP() がリトライごとに変わる）
UPDATE Users SET UpdatedAt = CURRENT_TIMESTAMP() WHERE ...;
```

## Go コード例

### 公式 SDK

```go
import "cloud.google.com/go/spanner"

count, err := client.PartitionedUpdate(ctx, spanner.Statement{
    SQL: `UPDATE Users SET Status = 'inactive'
          WHERE LastLoginAt < @threshold`,
    Params: map[string]interface{}{
        "threshold": thresholdTime,
    },
})
if err != nil {
    return fmt.Errorf("partitioned update failed: %w", err)
}
log.Printf("updated (lower bound) %d rows", count)
```

※ 戻り値の行数は**下限の概算**。正確な件数は返らない。

### インターリーブ子→親の順

```go
// 1. 子テーブルを先に削除
if _, err := client.PartitionedUpdate(ctx, spanner.Statement{
    SQL: `DELETE FROM LiveComments WHERE LiveCreatedAt < @threshold`,
}); err != nil { return err }

// 2. 親テーブルを削除
if _, err := client.PartitionedUpdate(ctx, spanner.Statement{
    SQL: `DELETE FROM Lives WHERE CreatedAt < @threshold`,
}); err != nil { return err }
```

## 通常 DML との使い分け

| 更新行数の目安 | 選ぶ手段 |
|----------------|----------|
| 〜数百行 | 通常 RW TX 内の DML |
| 数百〜数万行 | 通常 DML + バッチ分割（PK レンジで分割） |
| **数万行以上** | **Partitioned DML** |
| 時系列での自動削除 | **TTL (ROW DELETION POLICY)** |

## 参考

- [Partitioned DML | Spanner](https://cloud.google.com/spanner/docs/dml-partitioned)
