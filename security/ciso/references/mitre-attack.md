# MITRE ATT&CK フレームワーク リファレンス

## 概要

MITRE ATT&CK（Adversarial Tactics, Techniques, and Common Knowledge）は、実世界の観察に基づく敵対者の行動に関する知識ベース。SOC アナリスト、脅威ハンター、レッドチーム、セキュリティアーキテクトが共通言語として使用する。

## Enterprise ATT&CK 14 戦術

| # | Tactic ID | 戦術名 | 説明 |
|---|-----------|--------|------|
| 1 | TA0043 | Reconnaissance | 将来の作戦に備えた情報収集 |
| 2 | TA0042 | Resource Development | インフラ・ツール・アカウントの準備 |
| 3 | TA0001 | Initial Access | ネットワークへの最初の侵入 |
| 4 | TA0002 | Execution | 攻撃者のコード実行 |
| 5 | TA0003 | Persistence | 再起動やクレデンシャル変更を越えたアクセス維持 |
| 6 | TA0004 | Privilege Escalation | より高い権限の取得 |
| 7 | TA0005 | Defense Evasion | 検出回避（最多テクニック数） |
| 8 | TA0006 | Credential Access | クレデンシャルの窃取 |
| 9 | TA0007 | Discovery | 環境の調査・把握 |
| 10 | TA0008 | Lateral Movement | ネットワーク内の横展開 |
| 11 | TA0009 | Collection | 対象データの収集 |
| 12 | TA0011 | Command and Control | 侵害システムとの通信 |
| 13 | TA0010 | Exfiltration | データの持ち出し |
| 14 | TA0040 | Impact | システム・データの破壊・操作 |

## SOC アナリスト必須テクニック

### Initial Access
- **T1566** Phishing（.001 添付ファイル / .002 リンク / .003 サービス経由）
- **T1078** Valid Accounts（.001 デフォルト / .002 ドメイン / .003 ローカル / .004 クラウド）
- **T1190** Exploit Public-Facing Application
- **T1133** External Remote Services

### Execution
- **T1059** Command and Scripting Interpreter（.001 PowerShell / .003 cmd / .005 VBScript / .006 Python / .007 JavaScript）
- **T1053** Scheduled Task/Job（.005 Windows / .003 Cron）
- **T1047** Windows Management Instrumentation
- **T1204** User Execution（.001 リンク / .002 ファイル）

### Persistence
- **T1547.001** Registry Run Keys / Startup Folder
- **T1136** Create Account（.001 ローカル / .002 ドメイン / .003 クラウド）
- **T1543.003** Windows Service

### Privilege Escalation
- **T1055** Process Injection（.001 DLL / .003 Thread Hijacking / .012 Process Hollowing）
- **T1548.002** Bypass UAC

### Defense Evasion
- **T1027** Obfuscated Files or Information
- **T1070** Indicator Removal（.001 Event Log 消去 / .004 ファイル削除 / .006 Timestomp）
- **T1036.005** Match Legitimate Name or Location
- **T1562** Impair Defenses（.001 ツール無効化 / .002 ログ無効化）

### Credential Access
- **T1003** OS Credential Dumping（.001 LSASS / .002 SAM / .003 NTDS / .006 DCSync）
- **T1110** Brute Force（.001 推測 / .003 Password Spraying / .004 Credential Stuffing）
- **T1558** Steal or Forge Kerberos Tickets（.003 Kerberoasting / .001 Golden Ticket）

### Lateral Movement
- **T1021** Remote Services（.001 RDP / .002 SMB / .004 SSH / .006 WinRM）
- **T1570** Lateral Tool Transfer

### Command and Control
- **T1071** Application Layer Protocol（.001 HTTP/S / .004 DNS）
- **T1105** Ingress Tool Transfer
- **T1219** Remote Access Software（TeamViewer、AnyDesk 等）

### Exfiltration
- **T1048** Exfiltration Over Alternative Protocol
- **T1567.002** Exfiltration to Cloud Storage

### Impact
- **T1486** Data Encrypted for Impact（ランサムウェア）
- **T1490** Inhibit System Recovery（バックアップ削除）

## アラート → ATT&CK マッピング早見表

| アラート種別 | ATT&CK テクニック |
|-------------|-------------------|
| 不審な PowerShell 実行 | T1059.001 |
| 悪意ある添付ファイル付きメール | T1566.001 |
| 新規 Windows サービス作成 | T1543.003 |
| LSASS メモリアクセス | T1003.001 |
| 不審なスケジュールタスク作成 | T1053.005 |
| 複数の認証失敗後に成功 | T1110 / T1078 |
| ワークステーション間の RDP | T1021.001 |
| DNS トンネリング | T1071.004 |
| VSS シャドウコピー削除 | T1490 |
| UAC バイパス試行 | T1548.002 |
| エンコードされたコマンドライン引数 | T1027 |
| プロセスインジェクション | T1055 |
| 大量ファイル暗号化/リネーム | T1486 |
| イベントログ消去 | T1070.001 |
| Certutil によるファイルダウンロード | T1105 |
| 未承認リモートアクセスツール | T1219 |
| Pass-the-Hash | T1550.002 |
| Kerberoasting（RC4 TGS 要求） | T1558.003 |
| レジストリ Run Key 変更 | T1547.001 |
| ビーコンパターン通信 | T1071.001 |

## ATT&CK マトリクス

| マトリクス | 対象 | 概要 |
|-----------|------|------|
| Enterprise | Windows/macOS/Linux/Cloud/Network/Containers | 主要マトリクス（14戦術、200+テクニック、400+サブテクニック） |
| Mobile | Android/iOS | モバイルプラットフォーム向け（100+テクニック） |
| ICS | SCADA/PLC/DCS/HMI | 産業制御システム向け（12戦術） |

## ATT&CK Navigator

ATT&CK マトリクスを可視化・注釈するオープンソース Web アプリケーション。

### SOC での活用
1. **検出カバレッジヒートマップ**: テクニックごとに検出能力を色分け（緑=検出可能、黄=部分的、赤=未対応）
2. **脅威グループオーバーレイ**: 脅威グループの TTP と自組織の検出カバレッジを重ねてギャップを特定
3. **インシデント可視化**: 攻撃者が使用したテクニックをマッピングして視覚的な「攻撃ストーリー」を作成
4. **Purple Team 計画**: 次にテストするテクニックの計画
5. **成熟度追跡**: 異なる時点のカバレッジレイヤーを比較して改善を可視化

- Web: https://mitre-attack.github.io/attack-navigator/
- レイヤーは JSON / SVG / Excel でエクスポート可能

## MITRE D3FEND（防御テクニック）

ATT&CK の攻撃テクニックに対応する防御的対策の知識グラフ。

| カテゴリ | 説明 | 例 |
|---------|------|-----|
| Harden | 攻撃面縮小のための予防的措置 | アプリケーション/クレデンシャル/プラットフォーム強化 |
| Detect | 敵対者活動の識別能力 | ファイル/ネットワーク/プロセス/ユーザー行動分析 |
| Isolate | 封じ込め・セグメンテーション | サンドボックス、ネットワーク分離 |
| Deceive | 欺瞞技術 | ハニーポット、ハニートークン |
| Evict | 攻撃者アーティファクトの排除 | クレデンシャルローテーション、プロセス終了 |
| Restore | 復旧能力 | 設定復元、運用マッピング |

- https://d3fend.mitre.org/

## 関連ツール・リソース

| ツール | 概要 |
|--------|------|
| ATT&CK Navigator | マトリクス可視化・カバレッジ分析 |
| MITRE CAR | 検出ルールの知識ベース（https://car.mitre.org/） |
| MITRE CALDERA | 自動敵対者エミュレーション |
| MITRE Engenuity Evaluations | セキュリティ製品の独立評価 |
| ATT&CK Workbench | ローカルカスタマイズ版 ATT&CK 管理 |
| Sigma Rules | ATT&CK マッピング済み汎用検出ルール |
| Atomic Red Team | テクニック単位のテスト実行 |

## データソースモデル（ATT&CK v10+）

| データソース | データコンポーネント | ツール/ログ |
|-------------|---------------------|------------|
| Process | 作成、終了、アクセス、API 実行 | Sysmon (1,10)、EDR、Win Security (4688) |
| Command | コマンド実行 | PowerShell (4104)、Bash history |
| File | 作成、変更、削除、アクセス | Sysmon (11,23)、EDR |
| Network Traffic | 接続作成、フロー、コンテンツ | FW、NetFlow、Proxy、IDS、Zeek |
| Windows Registry | キー作成、変更、削除 | Sysmon (12,13,14) |
| User Account | 認証、作成、変更 | Win Security (4624,4625,4720) |
| Scheduled Job | 作成、変更 | Win Security (4698)、cron |
| Service | 作成、変更 | Win System (7045) |
| Active Directory | オブジェクトアクセス、変更、クレデンシャル要求 | Win Security (4662,4768,4769) |
| Cloud Service | 列挙、変更 | CloudTrail、Azure Logs、GCP Audit Logs |

## 検出品質の階層

1. **行動検出**（最良）: 特定ツールに依存しないテクニックの検出
2. **異常検出**: ベースラインからの逸脱
3. **シグネチャ検出**（最脆弱）: ハッシュ、ファイル名、コマンドライン文字列の一致
