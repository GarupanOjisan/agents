# 用語集

Cloud Spanner および ColorSing の Spanner 運用ドキュメントで頻出する略語・用語をアルファベット順に整理したもの。各項目は 1〜3 行で簡潔に説明する。

## 2PC (Two-Phase Commit)

分散トランザクションを Prepare / Commit の 2 フェーズで原子的に確定させるプロトコル。Spanner は複数 Split にまたがる書き込みを 2PC で処理するため、Split をまたぐトランザクションはレイテンシが増える。

## APPI（個人情報保護法）

日本の個人情報の保護に関する法律（Act on the Protection of Personal Information）。ColorSing では個人情報を扱うテーブルのデータ所在・暗号化・保持期間の設計に影響する。

## CDC (Change Data Capture)

データベースの変更（INSERT / UPDATE / DELETE）を下流システムへ連携する仕組み。Spanner では Change Streams がこれに相当する。

## CMEK (Customer-Managed Encryption Key)

顧客（組織）が Cloud KMS で管理する暗号鍵で Spanner データを暗号化する方式。鍵ローテーションや無効化を顧客側で制御できる。ColorSing では現状 GDEM を採用し CMEK は見送っている（`backup-policy.md` 参照）。

## CUD (Committed Use Discount)

Google Cloud の確約利用割引。一定期間の利用を確約する代わりに単価が下がる。Spanner でも PU / ノードに対して適用可能。

## CDC

→ [Change Data Capture](#cdc-change-data-capture)

## DDL / DML

- **DDL（Data Definition Language）**: `CREATE TABLE`、`ALTER TABLE`、`CREATE INDEX` などスキーマを定義・変更する文。
- **DML（Data Manipulation Language）**: `INSERT`、`UPDATE`、`DELETE` などデータを操作する文。Spanner では Partitioned DML という一括実行モードもある。

## DVT (Data Validation Tool)

Google 提供の OSS。異なるデータソース間のデータ整合性を検証するツールで、Spanner 移行やリストア検証で行数・チェックサム比較に使われる。

## FGAC (Fine-Grained Access Control)

行・列レベルでアクセス制御を行う仕組み。Spanner では行レベルセキュリティ相当の機能として提供される。

## GDEM (Google Default Encryption)

Google が管理する鍵で自動的に暗号化される既定の暗号化方式。顧客側の鍵管理は不要。CMEK の対義で語られる。

## IRE (Isolated Recovery Environment / Clean Room)

侵害されていないクリーンな環境でリストアを行うためのネットワーク的に隔離された環境。ランサムウェア対策で、プロダクション系統と独立した認証・権限境界を持つ。

## MVCC (Multi-Version Concurrency Control)

複数バージョンのデータを保持することで読み取りと書き込みの競合を避ける同時実行制御。Spanner は MVCC + TrueTime により強整合性 Stale Read を実現する。

## Org Policy（組織のポリシー制約）

Google Cloud の Organization Policy Service による組織レベルの制約。Spanner ではバックアップ削除禁止・リージョン制限などを組織ポリシーで強制できる。

## PITR (Point-in-Time Recovery)

過去の任意時点の状態にデータベースを復元する機能。Spanner は最大 7 日間の PITR をサポートする。論理削除や誤 DML からの復旧に用いる。

## PU (Processing Unit)

Spanner のキャパシティ単位。1 ノード = 1000 PU。小規模インスタンスでは PU 単位（100 PU から）で割り当てる。ストレージ上限や QPS 上限は PU 数に比例する。

## RACI

責任分担表の略。**R**esponsible（実行責任）、**A**ccountable（説明責任）、**C**onsulted（相談先）、**I**nformed（報告先）の 4 役割でタスクの担い手を明確化する。

## RO / RW トランザクション

- **RW（Read-Write）トランザクション**: 読み書き両方を行うトランザクション。ロックを取得するため競合時に待機・中断が発生する。
- **RO（Read-Only）トランザクション**: 読み取り専用。ロックを取らず並列性が高い。ColorSing では読み取り中心の処理は必ず RO を選ぶ。

## SLA / SLO / SLI

- **SLA（Service Level Agreement）**: 顧客との契約レベルの約束。未達時の補償を含む。
- **SLO（Service Level Objective）**: 社内の目標値。SLA より厳しく設定する。
- **SLI（Service Level Indicator）**: 実測指標（例: リクエスト成功率、p99 レイテンシ）。

## SMT (Spanner Migration Tool)

Google 提供の OSS。MySQL / PostgreSQL / CSV などから Spanner へのスキーマ・データ移行を支援する。

## TTL (Time To Live)

行の有効期限。Spanner では `ROW DELETION POLICY` でタイムスタンプ列を指定し、期限超過行を自動削除できる。ColorSing では対象テーブルすべてに TTL を設定するのが原則（`implementation-minimum-rules.md` ルール4）。

## VPC-SC (VPC Service Controls)

Google Cloud のサービスペリメータ機能。Spanner や GCS などの API 境界をプロジェクト横断で閉じ、データ持ち出しを防ぐ。

## WIF (Workload Identity Federation)

外部 ID プロバイダ（AWS、GitHub Actions、OIDC IdP など）から一時クレデンシャルで GCP リソースにアクセスする仕組み。長期鍵を配布せずに済む。

## WORM (Write Once Read Many)

一度書き込んだら変更・削除できないストレージ特性。Spanner 本体は WORM ではないが、バックアップを GCS の Object Lock（Bucket Lock）に退避することで WORM 特性を付与し、ランサムウェア耐性を高める。
