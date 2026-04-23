# ColorSing における Spanner バックアップ方針

> 本書は ColorSing 本番 Spanner データベースの保護方針を定める。法務レビュー済み。社内の個人情報保護・金融コンプライアンス要件（APPI / 資金決済法 / PCI-DSS 将来要件）を踏まえ、CISA #StopRansomware ガイド 2023（3-2-1-1-0 原則）、NIST SP 800-53 Rev 5 CP-9、CIS Controls v8.1 §11.4 に整合する構成を採用する。

## 1. バックアップの目的

### 1.1 なぜバックアップが必要か

ColorSing の本番 Spanner データベースは 192 テーブル（894 GB）を持ち、以下の事業上不可欠なデータを格納している。

- **ユーザー資産データ**: コイン残高（`UserCoinBalances`）、ダイヤモンド残高（`UserDiamondBalances`）、パール残高（`UserPearlBalances`）、出金台帳（`WithdrawalDiamondLedger`）
- **金融・決済データ**: 銀行口座情報（`UserBankAccounts`）、入金台帳（`DepositCoinLedger`）、Stripe 決済履歴、銀行振込履歴
- **個人情報（要配慮情報含む）**: 氏名・生年月日・性別・住所（アプリ層 envelope encryption で暗号化保存、§6.5 参照）
- **サービスコアデータ**: ユーザープロフィール、配信履歴、歌唱履歴、ランキング、ファン関係

これらのデータが失われた場合、サービスの継続が不可能になるだけでなく、ユーザーへの金銭的補償義務や法的責任が発生する。バックアップはあらゆるデータ損失シナリオに対する最後の防衛線である。

### 1.2 脅威分析

| # | 脅威カテゴリ | 具体例 | 発生確率 | 影響度 |
|---|------------|--------|---------|--------|
| T1 | オペレーションミス | 誤った DDL/DML 実行、スキーマ変更ミス | 中 | 高〜致命的 |
| T2 | アプリケーションバグ | 不正なデータ更新・削除の大量実行 | 中 | 高 |
| T3 | GCP プロジェクト権限の侵害 | フィッシング、AitM、SA キー漏洩による Spanner 管理者権限の奪取。PITR 無効化 → バックアップ全削除 → データ破壊のキルチェーン | 低 | 致命的 |
| T4 | ランサムウェア | データ暗号化・破壊。潜伏期間の中央値は 5 日、75 パーセンタイル 17 日（Mandiant *M-Trends 2024*, Dwell Time セクション） | 低 | 致命的 |
| T5 | 内部不正 | 管理者権限の悪用による静かなデータ改ざん（残高操作等）。Verizon DBIR 2024 では侵害のうち内部関与がおよそ 20% | **中** | 致命的 |
| T6 | **サプライチェーン攻撃** | CI/CD 経由の悪性 Terraform、SA インパーソネーション連鎖、gcloud CLI / Dataflow テンプレートのサプライチェーン、OSS 依存（npm/pip）経由の侵入 | 中 | 致命的 |
| T7 | **Organization 層の侵害** | Super Admin 乗っ取り、Workspace ドメインの引き継ぎ / Take-over、Org Policy の無効化 | 低 | 致命的 |
| T8 | **Google 側大規模障害・アカウント停止** | リージョン全域障害、ToS 違反による Billing Account / Organization 停止 | 極低 | 致命的 |
| T9 | **リーガルホールド / データ差押え** | 日本国内外の裁判所命令、捜査機関の令状執行 | 低 | 高 |
| T10 | **データ主権 / 越境規制** | APPI 越境移転制限（第 28 条）、顧客契約の国内保管義務、決済代行先審査 | 中 | 中 |
| T11 | **暗号破綻** | 量子計算機の実用化による RSA/ECC 破綻（長期的）、HSM ベンダ脆弱性 | 極低（長期） | 致命的 |

### 1.3 攻撃シナリオ: GCP プロジェクト管理者権限の侵害

攻撃者が `roles/spanner.admin` を取得した場合の具体的なキルチェーン:

1. `version_retention_period` を `1h` に変更（PITR の即時無効化）
2. `gcloud spanner backups delete` で全ネイティブバックアップを削除
3. 1 時間待機（PITR のバージョンデータが自動消失）
4. 全テーブルに対して `DELETE` / `DROP TABLE` を実行

**PITR と Spanner ネイティブバックアップは同一の信頼境界（GCP プロジェクト `singcolor`）内にあるため、上記攻撃で両方とも同時に無効化される。** この脅威に対応するには、信頼境界の外にある Immutable Vault（論理隔離 WORM）バックアップと、さらに別クラウドのオフサイトが有効。

### 1.4 ビジネス制約

**1 日以上前のバックアップに全データ復元するビジネス判断はかなり難しい。**

- ライブ配信サービスでリアルタイム取引（ギフト、コイン、ダイヤモンド換金）が常時発生
- 1 日以上前に巻き戻すとその間の全ユーザー間取引が消失し、実質サービス再起動に近い事態になる
- **ただし、テーブル単位・行単位の部分復元は有用**（例: `UserCoinBalances` だけを過去の状態に戻し、その後の入出金ログから再適用する等）

## 2. バックアップ方針

### 2.1 設計原則

1. **信頼境界の分離**: 同一 GCP プロジェクト内の復旧手段だけに依存しない。別プロジェクトに Immutable Vault（論理隔離 WORM）を配置し、さらに別クラウド／別組織への真のオフサイト（Layer 4）を選択肢として保持する
2. **テーブルのティア分類**: 全テーブル一律ではなく、重要度に応じてバックアップ戦略を変える
3. **部分復元の活用**: 全データ復元が困難なビジネス制約を踏まえ、テーブル単位の部分復元を前提とした設計にする
4. **コスト効率**: Spanner バックアップ（$0.30/GB/月）と GCS ストレージの価格差を活用し、長期保持は GCS に委譲する
5. **鍵と権限の分離**: CMEK を採用し、KMS 管理者・Spanner 管理者・Vault 管理者を 3 者分離する（§6.3 参照）
6. **SA キーの原則不使用**: Workload Identity Federation と short-lived credentials で代替し、`disableServiceAccountKeyCreation` と整合させる（§3.3 参照）

### 2.2 用語: Immutable Vault（論理隔離 WORM）

本方針で繰り返し言及する「Immutable Vault」は、**別 GCP プロジェクト + Bucket Lock (WORM) + `objectCreator` のみの最小権限**で構成する **論理隔離** を指す。

> **注**: ネットワーク経路（Google フロントエンド）と制御プレーン（GCP IAM / Org）は `singcolor` と共有されるため、**真の物理エアギャップではない**。Organization Super Admin 侵害時（T7）は Org Policy ごと無効化される可能性がある。この限界を埋めるのが後述の Layer 4（真のオフサイト）である。

### 2.3 多層防御アーキテクチャ

| 層 | 手段 | 保存先 | 保持期間 | 隔離種別 | 主な対応脅威 | 月額コスト（概算） |
|----|------|--------|---------|---------|-------------|------------------|
| **Layer 0** | PITR | Spanner 内部（同一インスタンス） | 7 日 | なし | T1, T2 | ~$27 |
| **Layer 1** | 日次フルバックアップ | Spanner マネージドストレージ（同一 PJ） | 3 日 | なし | 大規模データ破損、PITR フォールバック | ~$107 |
| **Layer 2** | 週次 Tier1 エクスポート | **別 PJ GCS（Nearline + Bucket Lock 90 日）** | 90 日 | **論理隔離（Immutable Vault）** | T3, T4, T5 | ~$59 |
| **Layer 3** | 月次フルエクスポート | **別 PJ GCS（Coldline/Archive + Bucket Lock 365 日）** | 365 日 | **論理隔離（Immutable Vault）** | 長期潜伏 APT、T9, T10 | ~$42 |
| **Layer 4（選択肢）** | 月次フル真オフサイト | AWS S3 Object Lock or 別 Organization GCS | 7 年 | **制御プレーン分離（真オフサイト）** | T6, T7, T8 | 現時点で未採用（§3.5 試算） |
| Dataflow / KMS / Sink 等の周辺 | エクスポート実行・鍵管理・監査転送 | — | — | — | — | $30〜80 + α |

**合計: 概算 $300〜400/月**（Layer 4 を除く。詳細は §4.3）

### 2.4 Layer 2 / Layer 3 の統合の意思決定

Layer 2（Nearline 90 日 Tier1）と Layer 3（Coldline 365 日フル）は対象データ・保持期間・階層が異なるが、運用上の差は薄い。以下のどちらを採用するかは **SRE Lead + Security Lead の合議で確定する** 必要がある。

- **選択肢 A（現状案 / 独立維持）**: Layer 2 = Tier1 のみ Nearline、Layer 3 = 全テーブル Coldline。ジョブと保持ポリシーを独立管理しシンプル。
- **選択肢 B（推奨 / Lifecycle 統合）**: 常に全テーブルをエクスポートし、GCS Lifecycle で `Nearline(30d) → Coldline(90d) → Archive(365d〜7y)` へ自動遷移。ジョブを一本化し、復元粒度は常に全テーブル対応。

初期導入は A、運用が安定した段階で B への移行を評価する。

### 2.5 各層の技術的特性

| 特性 | Layer 0: PITR | Layer 1: ネイティブ BK | Layer 2/3: GCS Vault | Layer 4: 真オフサイト |
|------|--------------|----------------------|--------------------|---------------------|
| 保存場所 | Spanner 内部 MVCC | Spanner マネージド内部ストレージ | GCS（別 PJ） | S3 Object Lock 等 |
| 信頼境界 | `singcolor` PJ 内 | `singcolor` PJ 内 | `singcolor-backup-vault` PJ | 別クラウド / 別 Organization |
| PJ Owner 侵害時 | `version_retention_period` 変更で無効化可能 | `backups delete` で削除可能 | **Bucket Lock により削除不可（論理隔離）** | **制御プレーンも分離** |
| Org Super Admin 侵害時 | 無効化可能 | 無効化可能 | Org Policy ごと剥奪される可能性 | **独立して生存** |
| 復元粒度 | DB 全体（任意の時刻） | DB 全体（バックアップ時点） | **テーブル単位で選択可能** | テーブル単位 |
| 復元時間（894 GB） | 数分 | 30 分〜2 時間 | 数時間〜半日（Dataflow Import） | Egress 待ちで半日〜数日 |
| データ形式 | Spanner 内部形式 | Spanner 内部形式 | Avro（テーブル単位ファイル） | Avro + SHA-256 manifest |

### 2.6 テーブルのティア分類

192 テーブルを重要度に応じて分類し、Layer 2（週次 Vault）の対象を決定する。

**Tier 1: クリティカル — 金銭・残高系（Layer 2 の対象、推定 ~400 GB）**

- `UserCoinBalances` / `UserCoinBalanceInOutHistories`（246 GB）
- `UserDiamondBalances` / `UserDiamondBalanceInOutHistories`
- `UserPearlBalances` / `UserPearlBalanceInOutHistories`
- `DepositCoinLedger` / `WithdrawalDiamondLedger`
- `UserBankAccounts` / `BankTransferRequests`
- `ListenerSendGiftHistories`（60 GB）
- `UserLiveSuperLikes`（~50 GB）
- `MembershipLedger`

**Tier 2: 重要 — ユーザー基盤（Layer 3 のフルエクスポートに含まれる）**

- `Users` / `UserProfiles` / `AuthProviders`
- `Lives` / `Organizations` / `OrganizationLivers`
- `OpeAuditLogs`（運営監査ログ）

**Tier 3: 再生成可能 — バックアップ優先度低（エクスポートから除外可）**

- `SyncBQ`（176 GB）— BigQuery 同期バッファ、再生成可能（ただし再生成は BigQuery 側のバックアップに依存、§6.4 参照）
- `TimelineRecommendBy*`（ROW DELETION 14 日）— BQ から再生成
- `OnAiredLives` / `LiveComments` / `LiveViewingSessions`（ROW DELETION 7 日）

### 2.7 RPO / RTO 目標

| シナリオ | RPO | RTO | 使用手段 | 復元方式 |
|---------|-----|-----|---------|---------|
| オペミス（誤 DML 等、T1） | 0 分（任意の時点） | 数分 | Layer 0: PITR | DB 全体復元 |
| 大規模データ破損（T2） | 最大 24 時間 | 30 分〜2 時間 | Layer 1: ネイティブ BK | DB 全体復元 |
| ランサムウェア / 権限侵害（T3, T4, T5） | 最大 7 日 | 数時間 | Layer 2: 週次 Vault | **テーブル単位の部分復元** |
| 長期潜伏 APT / 監査対応（T9 他） | 最大 30 日 | 半日〜1 日 | Layer 3: 月次 Vault | テーブル単位 / フォレンジック |
| Organization 侵害 / 大規模障害（T6, T7, T8） | 最大 30 日 | 1〜3 日 | Layer 4: 真オフサイト（採用時） | テーブル単位 |

### 2.8 脅威 × Layer 対応マトリクス

| 脅威 | L0 PITR | L1 Native BK | L2 Vault 週次 | L3 Vault 月次 | L4 オフサイト | Org Policy / IAM |
|------|:-:|:-:|:-:|:-:|:-:|:-:|
| T1 オペミス | ◎ | ○ | △ | △ | △ | — |
| T2 アプリバグ | ◎ | ○ | △ | △ | △ | — |
| T3 PJ 権限侵害 | × | × | ◎ | ◎ | ◎ | ○ |
| T4 ランサムウェア | × | × | ◎ | ◎ | ◎ | ○ |
| T5 内部不正 | × | × | ○ | ◎ | ◎ | ◎ |
| T6 サプライチェーン | × | × | △ | ○ | ◎ | ◎ |
| T7 Organization 侵害 | × | × | × | × | ◎ | — |
| T8 Google 側大規模障害 / 停止 | × | × | △ | △ | ◎ | — |
| T9 リーガルホールド | ○ | ○ | ◎ | ◎ | ◎ | — |
| T10 データ主権 | — | — | ○（国内リージョン固定） | ○ | △（国・クラウド選定依存） | ◎ |
| T11 暗号破綻 | × | × | △ | △ | △ | ◎（CMEK 方針＋移行計画） |

凡例: ◎ 強く有効 / ○ 有効 / △ 部分的に有効 / × 無効 / — 非該当

## 3. Immutable Vault の設計（Layer 2 / Layer 3）と真オフサイト（Layer 4）

### 3.1 アーキテクチャ

```
[singcolor PJ]                              [singcolor-backup-vault PJ]
┌──────────────────┐   Dataflow + Avro     ┌───────────────────────────┐
│  Cloud Spanner   ├──────────────────────▶│  GCS (Nearline, WORM 90d) │  ← Layer 2 週次
│  (主データベース)  │   Workload Identity   │                           │
│                  │     Federation        │  GCS (Coldline, WORM 365d)│  ← Layer 3 月次
└─────────┬────────┘                       └────────────┬──────────────┘
          │ Log Sink (Org Aggregated)                   │
          ▼                                             ▼
   ┌────────────────────────────┐         ┌──────────────────────────┐
   │  [singcolor-kms PJ]        │         │  KMS 管理者 = Vault 管理者│
   │  CMEK (HSM, 90d rotation)  │◀────────│  とは別の第3者グループ     │
   │  destroy_scheduled 30d     │         │                          │
   └────────────────────────────┘         └──────────────────────────┘
                                                       │
                                                       ▼（選択肢）
                                    ┌───────────────────────────────────┐
                                    │  Layer 4: AWS S3 Object Lock       │
                                    │  （別クラウド / 真の制御プレーン分離）│
                                    └───────────────────────────────────┘
```

### 3.2 GCP プロジェクト分割

| プロジェクト | 役割 | 管理者グループ |
|------------|------|--------------|
| `singcolor` | 本番 Spanner / アプリ基盤 | Spanner Admins |
| `singcolor-backup-vault` | Layer 2/3 GCS Vault、監査ログ Sink 宛先 | Vault Admins（Spanner Admins とは別） |
| `singcolor-kms` | CMEK 鍵管理（Spanner / GCS の KEK） | KMS Admins（Spanner/Vault とは別） |
| `singcolor-audit`（任意統合可） | Aggregated Sink、SIEM 連携 | Security Team |

### 3.3 IAM 設計（最小権限・SA キーなし）

**Workload Identity Federation を標準採用する。** `iam.disableServiceAccountKeyCreation` と整合させるため、SA キーは原則作成しない。

**バックアップ書き込み経路:**

- Dataflow ジョブは `singcolor-backup-writer@singcolor.iam.gserviceaccount.com` SA を **インパーソネーション** で実行
- ジョブをキックする Cloud Run / Scheduler は GKE WI または OIDC → WIF（`//iam.googleapis.com/projects/.../workloadIdentityPools/...`）経由で `iamcredentials.generateAccessToken` を呼び、short-lived token（max 12h）で動作
- SA の権限:
  - `roles/storage.objectCreator`（Vault GCS に対して。**delete/overwrite 不可**）
  - `roles/spanner.databaseReader`
  - `roles/dataflow.worker`
  - `roles/cloudkms.cryptoKeyEncrypterDecrypter`（CMEK 使用のため）

**Vault プロジェクト側（復旧経路）:**

- 平時は **人間もサービスも書き込み・削除権限を持たない**（`objectCreator` だけ）
- 復旧時は **PAM による時限アクセス付与** で対応:
  - IAM Conditions（`request.time < ...`）
  - Access Approval による上長承認
  - Breakglass アカウント（MFA ハードキー必須、利用は Security Lead への事前通報 + 事後監査）
- MFA（WebAuthn / Titan Key）必須、セッション 1 時間

**KMS プロジェクト側:**

- `roles/cloudkms.admin` は KMS Admins のみに付与、Spanner Admins / Vault Admins には一切付与しない
- これにより、Spanner 管理者権限が奪われても鍵の削除はできない
- 逆に KMS 管理者は Spanner / Vault データへの直接アクセス権を持たない（鍵の緊急無効化で論理遮断のみ可能）

### 3.4 Organization Policy による防御

以下をすべて Organization レベルで適用する。

| Constraint | 効果 |
|-----------|------|
| `constraints/storage.retentionPolicyNotLocked = DENY` | Bucket Lock 解除を禁止 |
| `constraints/iam.allowedPolicyMemberDomains` | 外部ドメインへの IAM 付与を禁止 |
| `constraints/iam.disableServiceAccountKeyCreation` | SA キー作成を禁止（WIF 前提） |
| `constraints/iam.automaticIamGrantsForDefaultServiceAccounts` | デフォルト SA への Editor 自動付与を防止 |
| `constraints/compute.requireOsLogin` | SSH 鍵管理を IAM に寄せる |
| `constraints/essentialcontacts.allowedContactDomains` | セキュリティ通知の受信ドメインを社内に限定 |
| `constraints/gcp.resourceLocations = in:asia-northeast1,asia-northeast2` | 保管先を日本国内リージョンに限定（APPI 第 28 条 / 顧客契約対応） |
| `constraints/gcp.restrictCmekCryptoKeyProjects = projects/singcolor-kms` | CMEK 鍵を KMS PJ に限定 |
| `constraints/gcp.restrictNonCmekServices` | CMEK 非対応のサービス利用を禁止 |
| `constraints/cloudkms.allowedProtectionLevels = HSM` | HSM 以上の鍵のみ許可 |
| **VPC Service Controls perimeter** | Spanner API / GCS API をペリメタに収容、外部への exfiltration を遮断 |
| **Access Transparency / Access Approval** | Google SRE による管理アクセスを可視化・承認制に（T8 の調査にも有効） |

### 3.5 Layer 4（真のオフサイト）: 選択肢と試算

現時点で **未採用** だが、ランサムウェアと Organization 侵害（T6, T7）の脅威が顕在化した際の導入候補として検討する。

**Layer 4a: AWS S3 Object Lock（推奨）**

- 別クラウドによる制御プレーン完全分離
- 月次フル（Tier1+Tier2 ≈ 600 GB）を Avro + SHA-256 manifest で転送、S3 Glacier Deep Archive に Compliance モード Object Lock、保持 7 年
- コスト試算（東京 `ap-northeast-1`）:
  - ストレージ: Glacier Deep Archive $0.00099/GB/月 × 600 GB × 84 ヶ月（7 年積み上げ後定常）≈ **$50/月**（定常時）
  - GCP Egress: $0.12/GB × 600 GB ≈ **$72/月**（月次転送時のみ）
  - S3 API / Restore 料金: 演習時のみ発生
  - 合計 概算 **$130〜150/月**

**Layer 4b: 別 Google Workspace テナント配下の別 Organization GCS**

- GCP 内に留まるため Egress は不要、運用学習コストは低い
- ただし Google ToS 違反で Workspace が停止される T8 にはやや弱い
- コスト概算 **$30〜50/月**

**導入判断基準:**

- ColorSing がランサムウェア報告を受ける、または PCI-DSS Level 1 / 金融代行先審査で「別クラウド保管」が要件化された段階
- この時は Layer 4a を採用する

## 4. 方針の根拠

### 4.1 現状の問題点

2026 年 4 月 12 日時点の本番環境:

- 自動バックアップスケジュール: 毎日 01:10 JST、**保持期間 1 日**
- PITR: **4 日間**（最大 7 日のところ未拡張）
- Immutable Vault / オフサイト: **なし**
- 全復旧手段が同一 GCP プロジェクト内 — 権限侵害で全滅するリスク
- CMEK 未導入、SA キー運用、Access Approval 未有効化

### 4.2 法的・コンプライアンス根拠（正確な条文引用）

**個人情報保護法（APPI）** — 法務レビュー済み

- **第 23 条（安全管理措置）**（2022 年改正後、旧第 20 条）: 個人データの漏えい・滅失・毀損の防止のため必要かつ適切な措置を講じる義務
- **個人情報保護委員会 ガイドライン（通則編）10-6**（物理的／技術的安全管理措置の例）: バックアップの実施、バックアップからの復元テストを「望ましい措置」として例示
- **第 28 条（外国にある第三者への提供の制限）**: 保管先のリージョンを国内に限定する（§3.4 の `resourceLocations` で実装）

**資金決済法 / 犯収法**

- **資金決済法 第 3 条**（前払式支払手段の定義）: ダイヤモンド（換金可能な残高）は前払式支払手段に該当しうる
- **資金決済法施行令 + 事務ガイドライン**: 未使用残高の記録保全・報告義務
- **犯収法**: 本人確認記録・取引記録の保存義務（出金台帳の長期保全根拠）

**国際標準**

- **NIST SP 800-53 Rev 5 CP-9**（Information System Backup）: バックアップの頻度・保持期間は「**組織が定める**」となっており、具体日数は規定されていない。本方針の「最低 90 日 / 365 日」は組織方針として定義
- **CISA #StopRansomware Guide (2023 update)**: **3-2-1-1-0 原則**（3 コピー、2 種類メディア、1 オフサイト、1 イミュータブル、エラー 0）を推奨。具体的保持日数の数値規定はない
- **CIS Controls v8.1 §11.4**（Establish and Maintain an Isolated Instance of Recovery Data）: 「組織裁量」で頻度・保持期間を定める
- **Mandiant M-Trends 2024**: グローバル侵入滞留時間の中央値 10 日、ランサムウェア事案の 75 パーセンタイル 17 日（引用箇所は "Dwell Time by Threat" セクション）

> **組織方針としての最低保持日数**: Layer 2 = 90 日、Layer 3 = 365 日。Mandiant の 75 パーセンタイル 17 日を 5 倍以上カバーし、APPI ガイドラインと資金決済法の実務運用にも整合する。

### 4.3 コスト根拠（再計算）

| 項目 | 単価 / 条件 | 月額コスト |
|------|----------|----------|
| Layer 0: PITR 7 日 | Spanner 内部（DB ストレージ増分） $0.50/GB/月 | ~$27 |
| Layer 1: 日次 BK 3 日 | Spanner バックアップ $0.30/GB/月 | ~$107 |
| Layer 2: 週次 Tier1 90 日 | GCS Nearline $0.016/GB/月 × 400GB × 12 世代保持均し | ~$59 |
| Layer 3: 月次フル 365 日 | GCS Coldline $0.004/GB/月 × 900GB × 12 世代 | ~$42 |
| Dataflow エクスポート実行 | vCPU $0.056/vCPU·h × 4 ワーカー × 週次 2h + 月次 4h ≈ 40 vCPU·h | ~$30〜80 |
| Log Sink GCS（Vault PJ 転送） | GCS Standard + 書き込み API | ~$5〜10 |
| Cloud KMS 呼び出し（CMEK） | $0.03 / 10,000 ops + HSM 鍵 $1/鍵/月 | ~$5〜15 |
| リハーサル用 Spanner インスタンス | 500 PU × 数時間 × 年 4 回 + 半年 1 回のフル | ~$15〜30（月次換算） |
| **合計（Layer 4 除く）** | | **$300〜400/月** |
| Layer 4a（AWS S3 Object Lock、採用時） | Glacier Deep Archive + 月次 Egress | +$130〜150 |

## 5. リストアリハーサル運用

詳細手順は [`restore-drill.md`](./restore-drill.md) に定義する。以下はガバナンス層の要約。

### 5.1 リハーサルの種類と頻度

| 頻度 | 種類 | 範囲 | 目的 |
|-----|------|------|------|
| **四半期ごと** | 部分復元リハーサル | Layer 2 → 隔離 PJ に Tier1 テーブル 3 本を Dataflow Import。行数・チェックサム検証、RTO 実測 | 日常的な復旧経路の健全性確認 |
| **半年ごと** | 全層フルリハーサル | Layer 0 / 1 / 2 / 3 の全層で復元動作確認 | 多層防御全体の健全性 |
| **年 1 回** | IRE 演習 | Isolated Recovery Environment（別 PJ のクリーンルーム）に Layer 2 + 監査ログから復元、ランサムウェア想定シナリオ | T4 / T6 対応力の実証 |

### 5.2 合格基準

- RTO 実測が目標（§2.7）の **150% 以内**
- 復元データの **行数 + SHA-256 チェックサム** が manifest と完全一致
- 監査証跡（Cloud Audit Logs、Sink 転送）が欠損なく Vault に残存

これを下回る場合、SRE Lead が **Severity 2 インシデント** として扱い、原因調査と是正を 2 週間以内に完了させる。

### 5.3 責任分担（RACI）

| 役割 | SRE Lead | Security Lead | Vault Admins | KMS Admins | 経営 |
|-----|:-:|:-:|:-:|:-:|:-:|
| 実施 | **R** | C | C | C | — |
| 最終承認 | A | **A** | — | — | I |
| 結果レビュー | R | R | R | R | **I** |

### 5.4 結果保存

リハーサル結果（RTO 実測、チェックサム一致有無、検出された逸脱）は Vault PJ のリハーサル専用バケット（WORM 5 年）に保存。監査・PCI-DSS Level 1 申請時に提出可能な形式（PDF レポート + JSON メタデータ）で保管する。

## 6. 期待する効果

### 6.1 データ保護の強化

| 指標 | 改善前 | 改善後 |
|------|-------|-------|
| PITR 対応期間 | 4 日 | 7 日（最大値） |
| ネイティブバックアップ保持 | 1 日（1 世代のみ） | 3 日（3 世代） |
| Immutable Vault | **なし** | 週次 90 日 + 月次 365 日（WORM） |
| プロジェクト権限侵害への耐性 | **なし（全滅）** | Layer 2/3 が独立して生存、L4 で Org 侵害にも対応可能 |
| CMEK | 未導入 | **HSM 90 日ローテーション、3 者分離** |
| SA キー | 多用 | **WIF + short-lived credentials で原則廃止** |
| 監査ログ保護 | Sink 未配置 | **Aggregated Sink + WORM バケット + 変更監視** |
| テーブル単位の部分復元 | 不可 | Layer 2/3 の Avro から可能 |
| リストアリハーサル | 未実施 | 四半期 / 半年 / 年 1 の 3 階層運用 |
| ランサムウェア潜伏期間のカバー | 1 日 | 90〜365 日（CISA 3-2-1-1-0 準拠） |

### 6.2 RPO / RTO の改善

- **RPO**: 最大 4 日（PITR のみ）→ 脅威に応じて **0 分〜最大 30 日**
- **RTO**: 手段がなく不明 → **数分〜3 日**（層ごとに明確）

### 6.3 コンプライアンス適合

- APPI 第 23 条・第 28 条・通則編ガイドライン 10-6 を充足
- 資金決済法 第 3 条 / 施行令 / 事務ガイドライン、犯収法の記録保全義務に対応
- NIST SP 800-53 CP-9・CISA 3-2-1-1-0・CIS v8.1 §11.4 に整合
- PCI-DSS Level 1 や金融代行先審査時の CMEK / Access Approval / HSM 要件を先取り

## 7. 補足方針

### 7.1 バックアップ完全性検証

エアギャップや論理隔離が存在しても、攻撃者が静かにデータを改ざんした後にバックアップが取られた場合、バックアップ自体が汚染されている。これに対応するため、以下を週次で自動実行:

- Tier1 テーブルの残高合計の異常変動検出（前週比、前月比、季節補正）
- Avro ファイルごとの SHA-256 チェックサム記録と manifest 整合性検証
- 異常検出時は即座に Security Lead へアラート

### 7.2 監査ログの保護

- **Organization Aggregated Sink** で全プロジェクトの Cloud Audit Logs（Admin Activity / Data Access / System Event / Policy Denied）を `singcolor-backup-vault` の専用 GCS バケットへ転送
- 転送先バケットにも **Bucket Lock（Retention 7 年）** を適用
- **Sink writer identity** の権限は Vault 側で `objectCreator` のみに制限
- **Sink 設定変更監視**: `SetSinks` / `UpdateSink` / `DeleteSink` の Admin Activity を Cloud Logging アラートで即時検知（T3, T6 の攻撃者が destination を書き換えるパスを遮断）
- **Sink エラーメトリクス**: `logging.googleapis.com/exports/error_count` のアラート設定で転送漏れを検知

### 7.3 暗号化方針（CMEK 採用）

**方針転換**: 従来の「CMEK は導入しない」から、**CMEK を標準採用する** に方針を転換する。

理由:

- Cloud KMS の鍵削除は `destroy_scheduled_duration = 30d`（最短 24 時間、本方針では **30 日**）でスケジュール削除にできるため、誤削除・悪意削除いずれも **30 日の猶予** が生まれる
- `roles/cloudkms.admin` を Spanner Admins / Vault Admins と **3 者分離** することで、Spanner 権限を奪った攻撃者が鍵を削除するパスを遮断できる
- 逆に攻撃者が Spanner 管理者権限を取った場合でも、KMS 管理者が別なら **鍵の緊急無効化（論理遮断）** により被害拡大を止められる
- APPI・PCI-DSS Level 1・金融代行先審査では CMEK がほぼ必須要件化しており、先行導入はビジネス上も合理的

**構成:**

- 保護対象: Spanner DB、Layer 2/3 GCS Vault、監査ログ Sink バケット、Layer 1 Spanner ネイティブバックアップ
- 保護レベル: **HSM**（`constraints/cloudkms.allowedProtectionLevels = HSM` で強制）
- ローテーション: **90 日自動**、旧鍵バージョンは `destroyed` ではなく `disabled` → 30 日猶予後 `destroy`
- 鍵バージョンの **export は不可**（`importOnly` は使わない、HSM で保持）
- KMS 監査ログを Aggregated Sink 経由で Vault に送信し、鍵の参照・無効化を追跡

**Org Policy による強制:**

- `constraints/gcp.restrictCmekCryptoKeyProjects = projects/singcolor-kms`
- `constraints/gcp.restrictNonCmekServices`（CMEK 非対応サービス利用禁止）
- `constraints/cloudkms.allowedProtectionLevels = HSM`

### 7.4 BigQuery との相互依存

Tier 3 `SyncBQ` および `TimelineRecommendBy*` の「再生成可能」は **BigQuery 側のバックアップに依存する**。具体的には:

- BigQuery Time Travel: 7 日（デフォルト）
- BigQuery Table Snapshot: 運用上 30 日以上を確保すること
- Fail-safe: 追加 7 日（Google 内部保持、ユーザー操作不可）

**BigQuery 側のバックアップ方針は本ドキュメントのスコープ外だが、BQ 方針との相互参照を必須とする。** BigQuery Snapshot / Time Travel の設計変更時は本方針も連動して見直す。

### 7.5 アプリ層 envelope encryption（個人情報の暗号化保存）

Spanner 上の氏名・生年月日・性別・住所は、GCP の at-rest CMEK に加えてアプリケーション層で envelope encryption を実施する。

- **KEK**: Cloud KMS（`singcolor-kms` PJ、HSM、90 日ローテーション）
- **DEK**: テーブル行または列グループ単位で生成、Spanner 内に KEK で暗号化して保存（`DEK_ENCRYPTED` 列）
- **復号経路**: アプリ SA が `cloudkms.cryptoKeyDecrypter` で DEK を復号 → メモリ上で PII を復号、レスポンス時に即廃棄
- **バックアップ上の扱い**: Layer 1/2/3 すべてに暗号化済み状態で保存される。復元時も KEK を KMS PJ から参照できる限り復号可能
- **KEK の喪失 = データ喪失**: KMS PJ は Vault 同等の重要度で運用する（§3.2）

### 7.6 Layer 4 未採用時のリスク受容の明記

現時点で Layer 4 を採用していないことは、T6（サプライチェーン）/ T7（Organization 侵害）/ T8（Google 側停止）に対する **明示的なリスク受容** である。経営・Security Lead に四半期ごとに報告し、ランサムウェア事案の報告頻度、PCI-DSS 要件の変化、顧客契約の変更をトリガーに導入判断する。
