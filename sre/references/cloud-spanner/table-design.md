# テーブル設計

Spanner のテーブルを設計する際に考慮すべきことをまとめる。

関連: [Spanner で最低限実装で気をつけること](./implementation-minimum-rules.md)

## 特定のエンティティに付随するデータはインターリーブする

[アーキテクチャ解説](./architecture.md) で説明したとおり、Spanner のデータは **Split** という単位で管理されており、各ノードが分担して管理している。複数の Split に分散されているデータを取る場合、複数のノードから結果を待つので、単一 Split の場合に比べてレイテンシが悪化する可能性が高い。

そこで**インターリーブ**を利用することで、データがすべて同じ Split に格納されることを保証できる。インターリーブとは、親テーブルに対して付随するデータを持つ子テーブルを定義する機能。

次のようなテーブル定義で、`Singers` テーブルに `Albums` テーブルをインターリーブできる。これによって、ある歌手のアルバム一覧を取得するクエリを発行すると 1 つの Split だけで処理が完結するため効率的。

```sql
CREATE TABLE Singers (
  SingerId   INT64 NOT NULL,
  FirstName  STRING(1024),
  LastName   STRING(1024),
  SingerInfo BYTES(MAX),
) PRIMARY KEY (SingerId);

CREATE TABLE Albums (
  SingerId     INT64 NOT NULL,
  AlbumId      INT64 NOT NULL,
  AlbumTitle   STRING(MAX),
) PRIMARY KEY (SingerId, AlbumId),
  INTERLEAVE IN PARENT Singers ON DELETE CASCADE;
```

## インターリーブを使うべき場面 / 避けるべき場面

**使うべき**:

- 親と子を一緒に読む操作が全体の 80% 以上
- 書き込み時に親子を同一トランザクションでまとめて書く
- 子テーブルの主要アクセスが「特定の親に属する子一覧」

**避けるべき**:

- 全親にわたって子テーブルを水平スキャンする（逆に遅くなる）
- 親 1 件に対して子行が数万〜数百万行（親+子合計 ~8GB 超）
- 多対多関係（インターリーブは 1 親のみ）

## 制約

- 最大深度 **7 レベル**（根テーブルを含む）
- TTL を使う親テーブルのインターリーブ子は **`ON DELETE CASCADE`** が必須
- 親 + 全子孫の合計が **8 GB 制限**

## ColorSing の設計判断例

### インターリーブ**しない**例: `UserCoinBalances` / `UserDiamondBalances`

`Users` に 1:1 で紐づく残高テーブルだが、以下の理由で**独立テーブル**にしている:

- **親子合計 8 GB 制限**: ユーザー数 × 残高履歴系がスケールするため、インターリーブすると `Users` ツリーが 8 GB に達しうる
- **全ユーザー横断集計**: 「総発行コイン量」「日次残高集計」など横断スキャンが頻繁に走るため、インターリーブ（= `Users` の Split に従属）では不利
- **独立した TTL / バックアップ運用**: 残高系のみ別ポリシーにしたい

### インターリーブ**する**例: `Lives` → `LiveComments`

以下の条件を満たすので適用している:

- 特定ライブのコメントを取得するクエリが支配的（80% 以上）
- ライブ終了時に親子まとめて削除（TTL + `ON DELETE CASCADE`）
- 1 ライブあたりのコメント数が有限（数千〜数万、8 GB に収まる）
- 全ライブを横断するコメント集計はほとんど発生しない

### 判断基準のまとめ

| 条件 | インターリーブする |
|------|---------------------|
| 親子を一緒に読む操作が 80%+ | ○ |
| 全親を横断した子テーブルのスキャンが主要 | × |
| 親 1 件あたり子が数万〜数百万行 | × |
| 親子合計 8 GB を超える見込み | × |
| 子テーブルを独立した TTL / 運用にしたい | × |

## コミットタイムスタンプ列（ColorSing 規約）

`CreatedAt` / `UpdatedAt` はすべて `TIMESTAMP` 型 + `OPTIONS (allow_commit_timestamp=true)` にし、書き込み時は `PENDING_COMMIT_TIMESTAMP()` を使う。

**スキーマ**:

```sql
CREATE TABLE Users (
  UserId    STRING(36) NOT NULL,
  Name      STRING(1024) NOT NULL,
  CreatedAt TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
  UpdatedAt TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
) PRIMARY KEY (UserId);
```

**書き込み（公式 SDK）**:

```go
m := spanner.InsertMap("Users", map[string]interface{}{
    "UserId":    userID,
    "Name":      name,
    "CreatedAt": spanner.CommitTimestamp,
    "UpdatedAt": spanner.CommitTimestamp,
})
```

**書き込み（DML）**:

```sql
INSERT INTO Users (UserId, Name, CreatedAt, UpdatedAt)
VALUES (@userId, @name, PENDING_COMMIT_TIMESTAMP(), PENDING_COMMIT_TIMESTAMP());
```

**メリット**:

- アプリ側のクロックずれ影響なし（Spanner の TrueTime ベース）
- トランザクションの順序と時刻順序が一致する
- Change Streams と組み合わせて正確な CDC が可能

**注意**:

- `PENDING_COMMIT_TIMESTAMP()` を書き込んだ**後**のレコードは同一 TX 内で読めない（`FutureReadTimestamp` エラー）
- `CreatedAt`/`UpdatedAt` を WHERE 句でフィルタしたい場合はインデックスに注意
