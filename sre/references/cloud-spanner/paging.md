# ページング

Cloud Spanner でページングを実現する際の方法。

## Cursor-based

テーブルの特定の列を基にしてページングを実現する方法。

下記のようなユーザー投稿のテーブルを想定する:

```sql
CREATE TABLE UserPosts (
  UserId    STRING(36) NOT NULL,
  PostId    STRING(36) NOT NULL,
  Body      BYTES NOT NULL,
  CreatedAt TIMESTAMP NOT NULL,
) PRIMARY KEY (UserId, PostId),
  INTERLEAVE IN PARENT Users ON DELETE CASCADE;
```

全ユーザーの投稿を新しい順でページングする場合、次のようなクエリを発行する。このクエリでは前のページの最後の投稿の作成日時より古い投稿を取得する。同一時刻の投稿の場合に安定してソートするため別の列（この例ではユーザー ID）を使ってソートする。

**ソート方向と不等号を揃える**: `ORDER BY` の方向（DESC / ASC）とタイブレーク列の比較演算子（`<` / `>`）は必ず揃える必要がある。例えば `ORDER BY CreatedAt DESC, UserId ASC` に対してタイブレークを `UserId >` にしてしまうと、DESC の並びの中で逆順に戻ってしまいページ境界で重複・欠落が起きる。両方を DESC に揃える、または両方を ASC に揃えるのがシンプル。

```sql
-- DESC で統一する場合（新しい順・UserId も降順）
SELECT * FROM UserPosts
WHERE
  CreatedAt < @PreviousCreatedAt
  OR (
    CreatedAt = @PreviousCreatedAt AND
    UserId < @PreviousUserId
  )
ORDER BY CreatedAt DESC, UserId DESC
LIMIT @Limit;
```

**インデックス設計の注意**: Cursor-based ページングを効率的に動かすには、ソートキーに沿ったセカンダリインデックス（例: `(CreatedAt DESC, UserId DESC)` を先頭に持つインデックス）が必須。加えて Spanner では基本的に `@{FORCE_INDEX=...}` でインデックスを明示することが推奨される（詳細は [FORCE_INDEX の使いどころ](./force-index.md)）。インデックスがない状態ではフルスキャンになり Offset-based と大差ない性能劣化を招く。

### ユースケース

後述する Offset-based のページングに比べると効率的にデータを取得できるので、キャッシュが難しいようなデータを扱う場合にはこの方法を使う。

## Offset-based

`LIMIT` 句と `OFFSET` 句を使ってページングを実現する方法。

**注意点**: OFFSET によって破棄された行もスキャンが実施される。`LIMIT m OFFSET n` を指定した場合、合計で `m + n` 行がスキャンされる。

さらに Spanner は分散 DB であるため、`LIMIT m OFFSET n` を指定したとき、**各ノードで `m + n` 行がスキャンされた後に結合処理が行われる**ためスキャンに一定以上のコストがかかる。

### ユースケース

以上を踏まえて、Offset-based のページングを使う場合はスキャン結果を一定期間キャッシュすることが前提であることが好ましい。

## 運用観点の補足（SRE レビュー）

### Cursor-based インデックス + FORCE_INDEX は必須

Cursor-based ページングで `(CreatedAt DESC, UserId DESC)` のようなソートキーを使う場合、**ソートキーに沿ったセカンダリインデックス** + **`@{FORCE_INDEX=...}`** が必須。運用上よくある事故:

- インデックスを張っただけで `FORCE_INDEX` を書き忘れ、オプティマイザが別プランを選んでフルスキャン化
- デプロイ初日は問題なくても、データが溜まると突然スキャン数が跳ね上がる
- クエリプランのレビューを **PR 時点で必ずスクリーンショット添付**させる

```sql
SELECT *
FROM UserPosts @{FORCE_INDEX=UserPostsByCreatedAtDesc}
WHERE
  CreatedAt < @PreviousCreatedAt
  OR (CreatedAt = @PreviousCreatedAt AND UserId < @PreviousUserId)
ORDER BY CreatedAt DESC, UserId DESC
LIMIT @Limit;
```

### カバリングインデックス化（STORING 列）

セカンダリインデックスに `STORING` 列を追加すると、ベーステーブルへの back-join が不要になりレイテンシ・CPU ともに改善する。

```sql
CREATE INDEX UserPostsByCreatedAtDesc
  ON UserPosts (CreatedAt DESC, UserId DESC)
  STORING (Title, ThumbnailUrl);
```

**STORING 列の選定方針**:

- **含める**: 一覧表示に必要な軽量列（タイトル、サムネイル URL、数値カウンタ）
- **含めない**:
  - **大きい列**（`BYTES(MAX)`、長文 TEXT）: インデックスサイズが肥大化、書き込みレイテンシ悪化
  - **頻繁に更新される列**: インデックスも同時更新されるため書き込みホットスポットの原因
  - **一覧で使わない詳細列**: 詳細 API で別途取得

**目安**:

- STORING 列の合計サイズは 1 行あたり **200 bytes 以内**
- 書き込み頻度が高い列は STORING せず back-join を受け入れる
- クエリプランで `distributed cross apply`（back-join）が出ていなければカバリング済み

### PR レビュー観点

- [ ] Cursor-based になっているか（Offset-based の場合はキャッシュ戦略が説明されているか）
- [ ] ソートキー用インデックスが存在するか（マイグレーションに含まれているか）
- [ ] `@{FORCE_INDEX=...}` が付いているか
- [ ] 必要に応じて STORING 列でカバリング化されているか
- [ ] カーソル値（`PreviousCreatedAt`, `PreviousUserId`）を API で署名 or 暗号化してクライアント改ざんを防いでいるか
- [ ] クエリプランのスキャン行数 / `distributed union` の有無が確認されているか
