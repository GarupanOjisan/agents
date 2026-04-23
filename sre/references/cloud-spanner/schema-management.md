# スキーマ管理

Spanner のスキーマ定義をどう管理するか。

## 管理方法

サーバーアプリケーションの変更とスキーマ定義の変更を関連付けたいので、サーバーアプリケーションのリポジトリにディレクトリを切って管理する。

## DDL の形式

次の 2 つの形式で管理することが考えられる。**結論: 2 の形式（差分形式）の方が運用しやすい。**

### 1. CREATE TABLE 形式でテーブルの完全な DDL を定義

後から追加した変更も `CREATE TABLE` の DDL に含める。

**メリット**:

- テーブルの定義がファイルから参照しやすい

**デメリット**:

- マイグレーションの一連のワークフローが定義できない
- 自動化のためのワークアラウンドも自分たちで用意する必要がある

```sql
CREATE TABLE Users (
  UserId    STRING(36) NOT NULL,
  Name      STRING(50) NOT NULL,
  CreatedAt TIMESTAMP NOT NULL,
  UpdatedAt TIMESTAMP NOT NULL,
  Age       INT64 NOT NULL, -- 後からカラムを追加
) PRIMARY KEY (UserId);

CREATE INDEX UsersByName ON Users (Name);
```

### 2. テーブルへの変更は ALTER TABLE 等で差分を別ファイルに定義（推奨）

時系列順に DDL を定義でき、テーブルへの変更は別ファイルで管理する。

**メリット**:

- マイグレーションの一連のワークフローが定義できる
- 既存のマイグレーションツール（[yo](https://github.com/cloudspannerecosystem/yo) など）を利用可能

**デメリット**:

- 最新のテーブル定義がファイルから見通しづらい

```sql
-- 001_create_users.sql
CREATE TABLE Users (
  UserId    STRING(36) NOT NULL,
  Name      STRING(50) NOT NULL,
  CreatedAt TIMESTAMP NOT NULL,
  UpdatedAt TIMESTAMP NOT NULL,
) PRIMARY KEY (UserId);

-- 002_add_age_to_users.sql
ALTER TABLE Users ADD COLUMN Age INT64;
-- 列の追加が完了後に NOT NULL に変更
ALTER TABLE Users ALTER COLUMN Age INT64 NOT NULL;
```

ColorSing では **差分形式** を採用している。
