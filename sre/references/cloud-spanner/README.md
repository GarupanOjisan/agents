# ColorSing における Cloud Spanner ドキュメント

> ColorSing 固有の Cloud Spanner 実装・運用ノウハウの **SSOT（Single Source of Truth）**。
> 汎用の Cloud Spanner ベストプラクティスは親ファイル [`../cloud-spanner.md`](../cloud-spanner.md) を参照。

## 想定読者

- **サーバーサイド開発者**（新入社員 〜 経験者）— Spanner を使った実装・デバッグ
- **SRE / インフラ担当** — キャパシティ、バックアップ、オートスケーリング、リストアリハーサル
- **PR レビュアー** — コミット前のチェックリストと設計レビュー観点
- **オンコール対応者** — ロック競合、ホットスポット、手動スケールなどの緊急対応

## 初読ロードマップ（新入社員向け）

この順番で読めば、ColorSing の Spanner 運用の前提に追いつける。

1. [はじめに](./introduction.md) — Spanner とは、PU、ストレージ上限
2. [アーキテクチャ解説](./architecture.md) — ノード / Split の理解
3. [テーブル設計](./table-design.md) — インターリーブ判断
4. [Spanner で最低限実装で気をつけること](./implementation-minimum-rules.md) — 絶対に守る 7 つのルール
5. [ロックの挙動について](./locking.md) — 楽観ロック + Redis 悲観ロック
6. [Stale Read の使い分け](./stale-reads.md) — 整合性と性能のトレードオフ
7. [PR チェックリスト](../cloud-spanner.md#812-colorsing-実装チェックリストpr-レビュー観点) — コミット前のセルフチェック

## 役割別クイックリンク

### 実装者

- [Spanner で最低限実装で気をつけること（7 ルール）](./implementation-minimum-rules.md)
- [Stale Read の使い分け](./stale-reads.md)
- [Transaction / Request タグ](./tags.md)
- [Partitioned DML](./partitioned-dml.md)
- [Change Streams](./change-streams.md)

### PR レビュアー

- [PR チェックリスト](../cloud-spanner.md#812-colorsing-実装チェックリストpr-レビュー観点)
- [ロックの挙動](./locking.md)
- [FORCE_INDEX の使いどころ](./force-index.md)

### オンコール

- [ロックの挙動](./locking.md)
- [オートスケーリング / 手動スケール](./autoscaling.md)
- [バックアップ方針](./backup-policy.md) / [リストアリハーサル](./restore-drill.md)

### SRE

- [バックアップ方針](./backup-policy.md)
- [リストアリハーサル](./restore-drill.md)
- [セッションプール設計](./session-pool.md)
- [オートスケーリング](./autoscaling.md)

## ドキュメント一覧

### 基礎知識

- [はじめに](./introduction.md)
- [アーキテクチャ解説](./architecture.md)
- [テーブル設計](./table-design.md)
- [ロックの挙動について](./locking.md)
- [Spanner のオートスケーリング](./autoscaling.md)

### 実装ルール

- [Spanner で最低限実装で気をつけること（7 ルール）](./implementation-minimum-rules.md)
- [Stale Read の使い分け](./stale-reads.md)
- [Partitioned DML](./partitioned-dml.md)
- [Change Streams](./change-streams.md)
- [Transaction / Request タグ](./tags.md)
- [セッションプール設計](./session-pool.md)

### Know-How

- [ページング](./paging.md)
- [FORCE_INDEX の使いどころ](./force-index.md)
- [バッチ処理の負荷分散](./batch-load-balancing.md)
- [カラムの追加](./add-column.md)

### ツール・ライブラリ（決定ログ）

- [スキーマ管理](./schema-management.md)
- [クエリテンプレートライブラリの選定](./query-template-library.md)
- [クエリビルダの選定](./query-builder.md)

### 運用方針

- [ColorSing における Spanner バックアップ方針](./backup-policy.md)
- [リストアリハーサル運用](./restore-drill.md)

### 補助

- [用語集](./glossary.md)

## 親ドキュメントとの関係

- 汎用の Cloud Spanner ベストプラクティス（スキーマ設計、クエリ最適化、監視、コスト、セキュリティ）は [`../cloud-spanner.md`](../cloud-spanner.md) を参照
- **親 `cloud-spanner.md` のセクション 8 と本ディレクトリの内容が重複する箇所は、本ディレクトリを正本（SSOT）とする**
- 親ファイルのセクション 8 は要約とリンク集にすぎず、詳細・最新版はすべてこのディレクトリにある
