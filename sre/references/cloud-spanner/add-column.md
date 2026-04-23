# カラムの追加

Spanner のテーブルに新規でカラム（列）を追加するとき、従来の MySQL のような RDBMS を使っているときに感じるギャップを元に注意点とノウハウをまとめる。

## NOT NULL なカラムの追加

Spanner では次のような DDL は実行できない。問題となるのは `NOT NULL` の指定:

```sql
-- 実行できない
ALTER TABLE Users ADD COLUMN Age INT64 NOT NULL;
```

Spanner で `NOT NULL` なカラムを後から追加したい場合は次のような手順で、NULL 許容なカラムを追加したあとで `NOT NULL` に変更する:

```sql
-- 1. NULL 許容なカラムを追加
ALTER TABLE Users ADD COLUMN Age INT64 DEFAULT (0);

-- 2. （必要に応じて）既存行のバックフィルを完了させる

-- 3. NOT NULL に変更
ALTER TABLE Users ALTER COLUMN Age INT64 NOT NULL;
```

**落とし穴**: `NOT NULL` への変更は、バリデーション完了前でも NULL 書き込みがほぼ即座に拒否される。アプリ側の書き込みに null が残っていないことを事前に確認する。

## AFTER の指定

テーブル定義の見通しを良くするためによく AFTER を指定してカラムを追加することがある。

```sql
-- Spanner では許可されない AFTER 句
ALTER TABLE Users ADD COLUMN Age INT64 NOT NULL AFTER Name;
```

しかし Spanner では AFTER を使用することはできない。**常にテーブルの最後にカラムが追加される**。
