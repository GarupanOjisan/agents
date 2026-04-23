# ColorSing Spanner リストアリハーサル運用手順

> 本書は [`backup-policy.md`](./backup-policy.md) §5 を実装する具体的な手順書である。四半期・半年・年 1 の 3 階層のリハーサルを運用可能な形で定義する。法務・監査レビュー対応を前提に、結果は Vault PJ のリハーサル専用バケット（WORM 5 年）に保存する。

## 1. 目的とスコープ

- バックアップの **論理的健全性**（ファイル存在、チェックサム一致）ではなく、**実際に復旧できること** を定期検証する
- RTO 実測値を継続的に計測し、§2.7 の目標との乖離を可視化する
- ランサムウェア / サプライチェーン攻撃（T4, T6）に対する IRE（Isolated Recovery Environment）復旧能力を保証する
- APPI 通則編 10-6、NIST SP 800-53 CP-4（Contingency Plan Testing）、CISA 3-2-1-1-0 原則の「0 = エラーゼロ確認」に対応

## 2. リハーサルの種類と頻度

| ID | 種類 | 頻度 | 範囲 | 対象環境 | 所要時間目安 |
|----|------|-----|------|---------|-------------|
| DR-Q | 部分復元 | 四半期（年 4 回） | Layer 2 の Tier1 テーブル 3 本 | 隔離 PJ `singcolor-drill` | 2〜4 時間 |
| DR-H | 全層フル | 半年（年 2 回） | Layer 0 / 1 / 2 / 3 すべて | 隔離 PJ `singcolor-drill` | 1 日 |
| DR-Y | IRE 演習 | 年 1 回 | Layer 2 + 監査ログ、クリーンルーム復旧 | IRE PJ `singcolor-ire`（通常は休眠） | 2〜3 日 |

すべて **本番サービスに影響を与えない独立 PJ** で実施する。

## 3. DR-Q: 四半期部分復元リハーサル

### 3.1 対象テーブル（ローテーション）

毎回 3 本、四半期ごとにローテーション:

- Q1: `UserCoinBalances`, `UserCoinBalanceInOutHistories`, `DepositCoinLedger`
- Q2: `UserDiamondBalances`, `WithdrawalDiamondLedger`, `UserBankAccounts`
- Q3: `UserPearlBalances`, `MembershipLedger`, `BankTransferRequests`
- Q4: `ListenerSendGiftHistories`, `UserLiveSuperLikes`, `Users`

### 3.2 事前準備

1. 隔離 PJ `singcolor-drill` に Spanner インスタンス（500 PU、Regional `asia-northeast1`）を作成
2. Vault PJ からのエクスポート Avro へのアクセス権を **時限付きで** `singcolor-drill-importer` SA に付与
   ```bash
   gcloud storage buckets add-iam-policy-binding gs://singcolor-backup-vault-layer2 \
     --member="serviceAccount:singcolor-drill-importer@singcolor-drill.iam.gserviceaccount.com" \
     --role="roles/storage.objectViewer" \
     --condition="expression=request.time < timestamp('${END_TIME}'),title=drill-window"
   ```
3. 計測用スプレッドシート（開始時刻、終了時刻、行数、SHA-256）を準備

### 3.3 実行手順

```bash
# Step 1: 最新の週次エクスポートパスを特定
export SRC="gs://singcolor-backup-vault-layer2/spanner-exports/$(gcloud storage ls gs://singcolor-backup-vault-layer2/spanner-exports/ | sort | tail -1)"
export DRILL_DB="projects/singcolor-drill/instances/drill-instance/databases/drill-${QUARTER}"
export START=$(date -u +%s)

# Step 2: 空 DB 作成
gcloud spanner databases create "drill-${QUARTER}" \
  --instance=drill-instance \
  --database-dialect=GOOGLE_STANDARD_SQL

# Step 3: スキーマ DDL 適用（本番から dump、PII カラムは暗号化済のまま）
gcloud spanner databases ddl update "drill-${QUARTER}" \
  --instance=drill-instance \
  --ddl-file=./schema/${QUARTER}.sql

# Step 4: Dataflow Import 実行（対象テーブル 3 本）
gcloud dataflow jobs run "drill-import-${QUARTER}" \
  --gcs-location=gs://dataflow-templates-asia-northeast1/latest/GCS_Avro_to_Cloud_Spanner \
  --region=asia-northeast1 \
  --staging-location=gs://singcolor-drill-staging/tmp \
  --parameters=instanceId=drill-instance,databaseId=drill-${QUARTER},inputDir=${SRC},tableFilter="${TABLE_1},${TABLE_2},${TABLE_3}"

# Step 5: 完了待ちと RTO 計測
gcloud dataflow jobs show "drill-import-${QUARTER}" --region=asia-northeast1 --format="value(currentState)"
export END=$(date -u +%s)
export RTO_SEC=$((END - START))
```

### 3.4 検証

#### 3.4.1 行数検証

```sql
-- 復元 DB 側
SELECT COUNT(*) AS restored_count FROM UserCoinBalances;
```

manifest に記録された `row_count` と一致すること（0 件差分）。

#### 3.4.2 チェックサム検証

エクスポート時に生成される `manifest.json` に各テーブルの SHA-256 が含まれる。復元後:

```bash
# Avro ファイルごとのハッシュを再計算して manifest と比較
for f in $(gcloud storage ls ${SRC}/UserCoinBalances*.avro); do
  gcloud storage objects describe "$f" --format="value(md5Hash,crc32c)"
done
```

加えて、復元 DB の主キー列に対して以下を実行し、論理レベルの一致を確認:

```sql
SELECT FARM_FINGERPRINT(STRING_AGG(CAST(UserId AS STRING) || ':' || CAST(Amount AS STRING) ORDER BY UserId))
FROM UserCoinBalances;
```

本番のスナップショット時点と一致すること。

#### 3.4.3 業務整合性チェック（サンプル）

- `UserCoinBalances.Balance` の合計 ≈ `DepositCoinLedger.Amount` の合計 − 既消費量（±1% 以内）
- 残高マイナスのレコードが 0 件

### 3.5 合格基準

- RTO 実測 ≤ 目標の **150%**（Layer 2 の RTO 目標「数時間」→ 6 時間以内）
- 行数完全一致、チェックサム完全一致
- 業務整合性チェック全通過

### 3.6 不合格時のエスカレーション

- 即座に **Severity 2 インシデント** を起票（PagerDuty `sre-drill` サービス）
- 24 時間以内に SRE Lead + Security Lead で原因分析会議
- 2 週間以内に是正、次回臨時 DR-Q を実施

### 3.7 後片付け

```bash
gcloud spanner databases delete "drill-${QUARTER}" --instance=drill-instance --quiet
# インスタンスは次回まで停止（PU を下げる）
gcloud spanner instances update drill-instance --processing-units=100
```

時限 IAM は期限で自動失効するが、明示的に revoke しても良い。

## 4. DR-H: 半年全層フルリハーサル

### 4.1 実施範囲

| Layer | 検証項目 |
|-------|---------|
| Layer 0 PITR | 過去 7 日以内の任意時刻への復元（新 DB 作成 → ランダムに選んだ 3 時点で復元） |
| Layer 1 ネイティブ BK | 最新 3 世代のバックアップそれぞれからの復元 |
| Layer 2 週次 Vault | 全 Tier1 テーブルを隔離 PJ に Import |
| Layer 3 月次 Vault | ランダムに選んだ過去 3 ヶ月分のフルエクスポートから 5% サンプルテーブルを Import |

### 4.2 追加検証

- **CMEK 鍵ローテーションのテスト**: 現在アクティブな鍵バージョンで復元できること、旧鍵（disabled 状態）で復元が失敗することを確認
- **Access Approval / Breakglass のテスト**: PAM 経由で時限アクセスを取得する経路が機能することを確認
- **Org Policy のテスト**: 意図的に制約違反のオペレーション（例: 外部ドメインへの IAM 付与）を試み、拒否されることを記録

### 4.3 合格基準

- 全 Layer の復元成功率 100%
- RTO 実測が §2.7 の層別目標の 150% 以内

## 5. DR-Y: 年次 IRE 演習（Clean Room）

### 5.1 想定シナリオ

ランサムウェア攻撃により `singcolor` PJ 全体が侵害されたと想定。`singcolor` PJ には一切アクセスせず、Vault PJ + KMS PJ + 事前取得した監査ログのみを用いて別クラウド / 別 Organization に復旧環境を構築する。

### 5.2 IRE 環境

- IRE PJ `singcolor-ire` は平時 **IAM policy が空**（誰もアクセスできない）
- 演習時にのみ Breakglass アカウントで `roles/owner` を時限付与
- ネットワークは本番 VPC と完全分離（VPC Service Controls で独立 perimeter）
- 演習終了後は IAM を全 revoke、Spanner インスタンスは削除

### 5.3 検証フロー

1. 侵害シナリオ通告（Red Team 役が仮想的にインシデント宣言）
2. Security Lead が Breakglass を使用し IRE PJ を起動
3. KMS PJ で緊急鍵状態を確認（disabled / active のどちらで復旧するかをシナリオで切り替え）
4. Vault PJ の最新 Layer 2 エクスポートを IRE PJ の Dataflow で Import
5. 監査ログ Sink からランサムウェア侵入起点を特定（Tier1 残高改ざんクエリを検出）
6. 復元 DB と最新 manifest の差分を検証（攻撃者の改ざん範囲を特定）
7. サービス再開条件（金融データの整合性、監査ログの完全性）を満たすことを確認
8. 終了後、IRE PJ の Spanner / GCS / IAM をすべて破棄

### 5.4 合格基準

- 72 時間以内にサービス再開可能な状態まで復元完了
- 改ざん検出の false negative が 0（Red Team が仕込んだ改ざんをすべて検出）
- 監査ログ欠損率 0%

### 5.5 結果の外部監査対応

DR-Y の結果レポートは、PCI-DSS Level 1 / ISMS / プライバシーマーク更新審査にそのまま提出できる形式で作成する。

## 6. RTO 実測方法

| フェーズ | 計測開始 | 計測終了 | 含むもの |
|---------|---------|---------|---------|
| 準備 | 演習宣言 | IAM / インフラ準備完了 | PAM 承認、PJ 起動 |
| 復元 | Dataflow ジョブ投入 | ジョブ `JOB_STATE_DONE` | Avro 読み取り、Spanner 書き込み |
| 検証 | 復元完了 | チェックサム一致確認 | SQL 集計、manifest 照合 |
| 全体 RTO | 演習宣言 | サービス再開可能判定 | 上記すべて |

各フェーズの秒単位 timestamp を `drill-results/${YEAR}/${ID}/timeline.json` に記録し、Vault リハーサルバケットに保存する。

## 7. 合格基準サマリとエスカレーション

| 基準 | 閾値 | 未達時の扱い |
|-----|-----|-------------|
| RTO 実測 | 目標の 150% 以内 | Sev 2、2 週間以内に是正 |
| 行数一致 | 差分 0 | Sev 1、48 時間以内に是正 |
| チェックサム一致 | 差分 0 | Sev 1、48 時間以内に是正（サイレントコラプションの疑い） |
| 業務整合性チェック | 全通過 | Sev 2 |
| 監査証跡完全性 | 欠損 0 | Sev 1（Sink 構成の緊急見直し） |

Sev 1: Security Lead が主導、経営報告必須。
Sev 2: SRE Lead が主導、四半期報告で経営共有。

## 8. 年次レポート形式

Vault リハーサルバケット `gs://singcolor-backup-vault-drill-reports/${YEAR}/` に以下を保存:

- `summary.pdf`: エグゼクティブサマリ（経営・監査向け）
- `timeline.json`: 各リハーサルの開始/終了 timestamp、RTO 実測
- `checksums.json`: テーブルごとの manifest と復元側ハッシュ
- `findings.md`: 検出された逸脱と是正状況
- `attestation.pdf`: SRE Lead / Security Lead の署名入り合格証明

バケットは Bucket Lock（Retention 5 年）で保護し、削除不可とする。

## 9. 監査対応

監査（外部、PCI-DSS、ISMS、プライバシーマーク）依頼時は以下を提示:

1. 本書（手順書）
2. 過去 3 年分の年次レポート（`summary.pdf` + `attestation.pdf`）
3. Vault リハーサルバケットの retention policy と Bucket Lock の設定証跡
4. RACI（[`backup-policy.md`](./backup-policy.md) §5.3）

Access Transparency ログを併せて提示することで、Google 側のアクセス有無も説明可能にする。

## 10. 改訂履歴

| 日付 | 版 | 変更内容 | 承認 |
|-----|----|---------|------|
| 2026-04-23 | 1.0 | 初版。backup-policy.md §5 の運用手順を切り出し | SRE Lead / Security Lead |
