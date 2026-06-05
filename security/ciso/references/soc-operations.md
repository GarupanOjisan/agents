# SOC 運用基礎 リファレンス

## SOC ティア構造

### Tier 1 — アラートアナリスト / トリアージアナリスト
- 24/7 で SIEM ダッシュボードとアラートキューを監視
- 初期トリアージ: 真陽性 vs 偽陽性の分類
- SOP / ランブックに従った対応
- 確認済み/複雑なインシデントを Tier 2 にエスカレーション
- チケットシステムへの初期所見の記録
- 必要スキル: 基本的なネットワーキング、ログ読解、ツール操作
- 関連資格: CompTIA Security+, CySA+, GSOC

### Tier 2 — インシデントレスポンダー / 深掘りアナリスト
- エスカレーションされたインシデントの深掘り調査
- ホスト・ネットワークフォレンジック
- 複数ログソースの相関分析
- スコープ、影響、根本原因の特定
- 検出ルールの開発・改善
- 封じ込め・修正アクションの調整
- 必要スキル: フォレンジック、マルウェア分析基礎、スクリプティング
- 関連資格: GCIH, ECIH, CHFI

### Tier 3 — 脅威ハンター / 上級アナリスト / SME
- 仮説駆動の脅威ハンティング
- 高度マルウェア分析・リバースエンジニアリング
- 新規検出コンテンツの開発・既存ルールのチューニング
- Red Team / Purple Team 演習の実施
- 脅威インテリジェンスレポートと TTP マッピング
- 必要スキル: 高度フォレンジック、RE、脅威インテリジェンス
- 関連資格: GCIA, GREM, GCFA, GSOM, OSCP

### SOC マネージャー
- 戦略的監督、予算管理、人員配置
- KPI/メトリクスの定義と追跡
- ステークホルダーへのコミュニケーション・経営層レポート
- SOC 成熟度改善イニシアチブの監督

## SOC 成熟度モデル

| レベル | 名称 | 特徴 |
|--------|------|------|
| 1 | 初期/アドホック | 正式プロセスなし、リアクティブのみ、最小限のツール |
| 2 | 管理的/定義済み | 基本プロセス文書化、SIEM 導入、限定的な相関 |
| 3 | 定義済み/標準化 | 標準化プロセス、プレイブック使用、定期レポート、TI 統合 |
| 4 | 定量的管理 | メトリクス駆動、自動化対応（SOAR）、脅威ハンティング |
| 5 | 最適化 | 継続的改善、AI/ML 強化、ATT&CK 完全カバレッジ、Purple Team |

## SOC メトリクス・KPI

### 検出メトリクス
| メトリクス | 説明 | 目標値 |
|-----------|------|--------|
| MTTD | 侵害から検出までの平均時間 | 分〜時間（日数は不可） |
| 検出カバレッジ | ATT&CK テクニックに検出ルールがある割合 | 継続的に向上 |
| 偽陽性率 | 全アラートに対する FP の割合 | 成熟 SOC: 20%未満 |
| アラート量 | アナリスト1名あたりのアラート数/シフト | ~20-25 対応可能アラート/8h |

### 対応メトリクス
| メトリクス | 説明 | 目標値 |
|-----------|------|--------|
| MTTR | 検出から対応完了まで | 自動化: 分、複雑: 時間 |
| MTTA | アラートからアナリストが着手するまで | 分単位 |
| MTTC | 検出から封じ込めまで | 最小化 |

### 運用メトリクス
- インシデント数（月/四半期、重大度別）
- エスカレーション率（Tier 1 → Tier 2）
- アナリスト稼働率
- プレイブックカバレッジ（アラートタイプに対する文書化手順の割合）
- SLA 遵守率
- アナリスト離職率

## SOC ツールカテゴリ

### SIEM（Security Information and Event Management）
| 製品 | ベンダー | 特徴 |
|------|---------|------|
| Google Security Operations (Chronicle) | Google | クラウドネイティブ、12ヶ月ホットデータ、YARA-L |
| Splunk Enterprise Security | Cisco/Splunk | SPL、Risk-Based Alerting、CIM |
| Microsoft Sentinel | Microsoft | KQL、Azure ネイティブ、Fusion 検出 |
| Elastic Security | Elastic | オープンソースコア、EQL、ES\|QL |
| IBM QRadar | IBM | AQL、Offense 相関、フローベース分析 |

### SOAR（Security Orchestration, Automation, and Response）
| 製品 | ベンダー | 特徴 |
|------|---------|------|
| Chronicle SOAR | Google | Security Operations 統合、Gemini AI |
| Cortex XSOAR | Palo Alto | 800+ 統合、War Room、ML |
| Splunk SOAR (Phantom) | Cisco/Splunk | Splunk ES 統合 |
| Tines | Tines | ノーコード自動化 |

### EDR（Endpoint Detection and Response）
| 製品 | ベンダー | 特徴 |
|------|---------|------|
| CrowdStrike Falcon | CrowdStrike | 軽量エージェント、Threat Graph、IOA |
| Microsoft Defender for Endpoint | Microsoft | M365 統合、AIR |
| SentinelOne | SentinelOne | AI 駆動、自律対応 |
| Cortex XDR | Palo Alto | Causality Chain、BIOC |

### NDR（Network Detection and Response）
| 製品 | ベンダー | 特徴 |
|------|---------|------|
| Darktrace | Darktrace | AI 駆動、自己学習 |
| ExtraHop Reveal(x) | ExtraHop | 暗号化トラフィック分析 |
| Vectra AI | Vectra | アイデンティティ脅威検出 |
| Corelight | Corelight | Zeek ベース |

### TIP（Threat Intelligence Platform）
| 製品 | ベンダー | 特徴 |
|------|---------|------|
| Google Threat Intelligence | Google | VirusTotal + Mandiant + Google |
| Recorded Future | Recorded Future | NLP 駆動インテリジェンス |
| MISP | オープンソース | コミュニティ共有プラットフォーム |
| OpenCTI | オープンソース | STIX/TAXII ネイティブ |

## SIEM クエリ言語比較

### Splunk SPL
```spl
index=windows sourcetype=WinEventLog:Security EventCode=4625
| stats count by src_ip, user
| where count > 10
| sort -count
```

### Microsoft KQL
```kql
SecurityEvent
| where EventID == 4625
| summarize FailCount = count() by SourceIP, Account
| where FailCount > 10
| order by FailCount desc
```

### Elastic EQL
```eql
authentication where event.outcome == "failure"
| stats count(event.id) by source.ip, user.name
| filter count >= 10
```

### Google Chronicle YARA-L 2.0
```
rule failed_login_brute_force {
  meta:
    severity = "High"
    technique = "T1110"
  events:
    $login.metadata.event_type = "USER_LOGIN"
    $login.security_result.action = "BLOCK"
    $login.principal.ip = $src_ip
  match:
    $src_ip over 10m
  condition:
    #login >= 10
}
```

## NIST Cybersecurity Framework (CSF) 2.0

### 6つのコア機能

| 機能 | ID | SOC との関連 |
|------|-----|-------------|
| **GOVERN** | GV | リスク管理戦略、ポリシー、役割・責任（2.0 で新設） |
| **IDENTIFY** | ID | 資産管理、リスク評価 |
| **PROTECT** | PR | アクセス制御、データセキュリティ |
| **DETECT** | DE | 継続的監視、異常・イベント分析（SOC の主要領域） |
| **RESPOND** | RS | インシデント管理、分析、緩和 |
| **RECOVER** | RC | 復旧計画実行、コミュニケーション |

### 実装ティア
- Tier 1: Partial（部分的）
- Tier 2: Risk Informed（リスク認識）
- Tier 3: Repeatable（再現可能）
- Tier 4: Adaptive（適応的）

## NIST SP 800-53 Rev. 5（SOC 関連コントロール）

| ファミリ | 名称 | SOC 関連度 |
|---------|------|-----------|
| AU | Audit and Accountability | ログ管理、監査証跡 |
| IR | Incident Response | IR-1〜IR-10: ポリシー、訓練、テスト、ハンドリング |
| SI | System and Information Integrity | SI-4: システム監視（SOC の中核） |
| CA | Assessment, Authorization, and Monitoring | 継続的監視 |
| AC | Access Control | ユーザーアクセス監視 |
| IA | Identification and Authentication | 認証監視 |

## GIAC/SANS 資格体系

| 資格 | 対象 | コース |
|------|------|--------|
| GSOC | SOC エントリーレベル | SEC450 |
| GCIA | ネットワーク侵入分析 | SEC503 |
| GCIH | インシデントハンドリング | SEC504 |
| GSOM | SOC マネジメント | SEC450 |
| GCFA | 高度フォレンジック | FOR508 |
| GREM | マルウェアリバースエンジニアリング | FOR610 |
| GCTI | サイバー脅威インテリジェンス | FOR578 |

## 脅威ハンティング手法

| 手法 | 説明 | 例 |
|------|------|-----|
| 仮説駆動 | 脅威インテリジェンスに基づく仮説を検証 | 「APT29 が WMI 持続性を使うなら、異常な WMI サブスクリプションがあるはず」 |
| IOC ベース | 既知の悪性インジケータを検索 | ハッシュ、IP、ドメインの検索 |
| データ駆動/異常ベース | 統計的外れ値やベースライン逸脱を分析 | ML による異常検出 |
| TTP ベース | ATT&CK テクニックに焦点を当てたハンティングクエリ | テクニック T1053 の全パターンを検索 |
| PEAK | Mandiant のフレームワーク: Prepare → Execute → Act → Knowledge | 構造化ハンティングサイクル |

## Palo Alto Networks Cortex プラットフォーム

### Cortex XDR
- エンドポイント、ネットワーク、クラウド、サードパーティのデータを統合
- **Causality Chain**: 関連アラートを因果関係でインシデントにグループ化
- **BIOC ルール**: 行動ベースのカスタム検出ルール
- **XQL**: SQL ライクなクエリ言語
- SOC ワークフロー: インシデントキュー → 因果関係ビュー → タイムラインビュー → 対応アクション

### Cortex XSOAR
- 800+ 統合のプレイブックプラットフォーム
- War Room: インシデント単位のコラボレーション空間
- インジケータ管理: IOC のライフサイクル管理
- 主要プレイブック: フィッシング、マルウェア、ランサムウェア、脆弱性管理

### Cortex XSIAM
- SIEM + SOAR + ASM + XDR の統合プラットフォーム
- AI/ML 駆動の自律 SOC
- Bring Your Own ML（BYOML）
- MITRE ATT&CK カバレッジダッシュボード

### Unit 42
- 脅威インテリジェンス・IR チーム
- 脅威リサーチ、攻撃グループプロファイル、脅威ブリーフ
- WildFire: クラウドベースのマルウェアサンドボックス
- AutoFocus: 脅威インテリジェンスポータル

## 主要年次レポート

| レポート | 発行元 | 内容 |
|---------|--------|------|
| M-Trends | Mandiant/Google | 滞留時間、攻撃ベクター、業界動向 |
| Global Threat Report | CrowdStrike | 脅威アクター、ブレイクアウト時間 |
| Ransomware Threat Report | Unit 42 | ランサムウェア動向、身代金統計 |
| DBIR | Verizon | データ侵害分析 |
| Cost of a Data Breach | IBM | 侵害の財務影響 |
| Threat Detection Report | Red Canary | 観測 ATT&CK テクニック |
| SOC Survey | SANS | SOC 運用ベンチマーク |
