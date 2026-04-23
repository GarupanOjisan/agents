# Change Streams

Spanner の **Change Streams** はテーブル変更（INSERT/UPDATE/DELETE）を**永続的に記録**し、ストリーム型で読み取れる機能。CDC (Change Data Capture) 用途。

## 用途

- **Transactional Outbox 代替**: `AfterCommit` と違い、Spanner 側で確実に永続化されるため配信漏れが起きない
- **BigQuery 連携**: Dataflow テンプレートでほぼノーコードで BQ 同期
- **Pub/Sub 連携**: 変更イベントを Pub/Sub に流して下流システムへ
- **検索インデックス同期**: Elasticsearch / Vertex AI Search への反映
- **監査ログ**: 誰が何をいつ変更したかを完全に記録

## ColorSing での想定利用

**現状**: 未導入（`AfterCommit` による Pub/Sub 発行で運用）

**導入候補**:

- `UserCoinBalances` / `UserDiamondBalances` などクリティカルな残高変更の BigQuery リアルタイム同期（会計・分析基盤向け）
- `Lives` の状態変更（配信開始 / 終了）を下流の通知システムに確実配信
- `Followings` の INSERT を推薦エンジンに連携

## 保持期間

- **公式仕様**: 1 日 〜 **30 日**（`retention_period` オプションで設定、デフォルト **1 日**）
- **ColorSing 推奨**: **3〜7 日**（Dataflow パイプライン障害時の復旧余裕を持たせつつ、ストレージコストを抑える）
- 短いほどストレージコストは下がるが、下流パイプライン停止時のデータロスリスクが上がる
- 金銭・監査など重要用途では保持期間を長め（7 日以上）に設定

## Co-location 設計

Change Streams のレコードは**変更対象テーブルと同一のトランザクションで書き込まれる**ため、以下が保証される:

- トランザクションが commit されれば Change Stream にも必ず記録される
- トランザクションが rollback されれば Change Stream にも記録されない
- **アプリケーション側で明示的に書く必要はない**（Spanner が自動で書く）

```sql
-- Change Stream の定義例
CREATE CHANGE STREAM UserBalanceChangeStream
  FOR UserCoinBalances, UserDiamondBalances
  OPTIONS (retention_period = '3d');

-- データベース全体を監視
CREATE CHANGE STREAM AllChangesStream
  FOR ALL
  OPTIONS (retention_period = '7d');
```

## Dataflow パイプライン停止時のデータロス閾値

- パイプラインが停止してから **`retention_period` で設定した期間（ColorSing では 3〜7 日）** 以内に復旧すればデータロスなし
- 保持期間を超えると古い変更レコードから順に破棄される
- **監視**: Dataflow Job のラグメトリクスを監視し、保持期間の 50% を超えたらアラート（例: 3 日保持なら 36 時間ラグでアラート）

## AfterCommit との比較

| 観点 | AfterCommit | Change Streams |
|------|-------------|----------------|
| 配信保証 | ベストエフォート（プロセスクラッシュで消失） | **At-least-once 保証**（Spanner に永続化） |
| 遅延 | commit 直後（ms 単位） | 秒オーダー（Dataflow 経由） |
| セットアップ | アプリコードのみ | Change Stream + Dataflow / 自前 Reader |
| 運用コスト | 低 | Dataflow 料金 + Spanner ストレージ |
| 用途 | 通知など多少の欠損許容 | **金銭・監査など確実性必須** |

**結論**: `AfterCommit` はプロセス落ちで消失する。金銭や監査用途は Change Streams に移行すべき。

## 参考

- [Change Streams 概要 | Spanner](https://cloud.google.com/spanner/docs/change-streams)
- [Dataflow テンプレート | Spanner → BigQuery](https://cloud.google.com/dataflow/docs/guides/templates/provided/cloud-spanner-change-streams-to-bigquery)
