# FORCE_INDEX の使いどころ

## FORCE_INDEX とは

`FORCE_INDEX` 句を使うことで、クエリでセカンダリインデックスを使うことを強制できる。

```sql
SELECT * FROM Users@{FORCE_INDEX=UsersIndexHoge} WHERE ~
```

## 基本的に使用するべき

Cloud Spanner はマネージドデータベースであり、クエリの実行計画を建てるオプティマイザや統計情報は Google によって管理されている。したがって、**昔はインデックスが使えていたのに、ある時点から急にインデックスが使われなくなりパフォーマンスが悪化することがあり得る**（実際にあった）。

そういった背景から、`FORCE_INDEX` 句は基本的には指定する。

## 使用を避けるべきケース

### 大量のレコードをスキャン、かつカバリングインデックスではない場合

Spanner ではセカンダリインデックスは通常のテーブルと同様に扱われるため、カバリングインデックスとならないようなクエリを発行すると、不足しているカラムを結合によって補う。

次のクエリではインデックステーブルに `Name` 列が含まれないため、インデックススキャン後にテーブルスキャンの結果との結合処理が実行される。

スキャンするレコード数が少数の場合には影響は無視できる程度だが、大量のレコードをスキャンするようなクエリで結合処理が発生すると影響は大きい。このような場合は、スキャン範囲を絞るか、カバリングインデックスにできないか検討する。

```sql
-- テーブル定義
CREATE TABLE Users (
  UserId STRING(36) NOT NULL,
  Name   STRING(MAX) NOT NULL,
  Age    INT64 NOT NULL,
) PRIMARY KEY (UserId);

CREATE INDEX UsersByAge ON Users (Age);

-- 結合が発生するクエリ（Name がインデックスにないため）
SELECT UserId, Name, Age
FROM Users@{FORCE_INDEX=UsersByAge}
WHERE Age = 20;
```

`STORING` 句でカバリング化する例:

```sql
-- STORING に Name を含めることで、Age で引いたあとのテーブル結合（バックジョイン）を回避できる
CREATE INDEX UsersByAge ON Users (Age) STORING (Name);
```
