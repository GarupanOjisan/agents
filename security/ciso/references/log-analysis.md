# ログ分析 リファレンス

## 主要ログソース

### エンドポイントログ
- Windows Event Logs（Security, System, Application, Sysmon, PowerShell）
- Linux: syslog, auth.log, audit.log（auditd）
- macOS: Unified Logging（log show）
- EDR テレメトリ（プロセス実行、ファイル変更、ネットワーク接続、レジストリ変更）

### ネットワークログ
- ファイアウォールログ（allow/deny、NAT）
- プロキシ/Web ゲートウェイログ（URL、User-Agent、Content-Type）
- DNS クエリログ
- IDS/IPS アラート（Snort、Suricata）
- NetFlow / IPFIX
- VPN ログ
- Zeek（旧 Bro）接続、HTTP、DNS、SSL、ファイルログ

### 認証/アイデンティティ
- Active Directory ログ（DC の Security Events）
- Azure AD / Entra ID Sign-in/Audit ログ
- RADIUS/TACACS+ ログ
- SSO/IdP ログ（Okta、Ping、OneLogin）
- MFA プラットフォームログ

### クラウドログ
- **GCP**: Cloud Audit Logs、VPC Flow Logs、SCC Findings
- **AWS**: CloudTrail、VPC Flow Logs、GuardDuty、S3 Access Logs
- **Azure**: Activity Log、Azure AD Logs、NSG Flow Logs
- **Kubernetes**: Audit Logs、Container Runtime Logs

### アプリケーションログ
- Web サーバー（Apache、Nginx、IIS）
- データベース監査ログ
- メールゲートウェイ（Exchange、O365 Message Trace、Google Workspace）
- DLP アラート
- SaaS 監査ログ

## Windows Event ID クイックリファレンス

### 認証イベント

| Event ID | ログ | 説明 | SOC 重要度 |
|----------|------|------|-----------|
| **4624** | Security | ログオン成功 | 高 — LogonType で分析 |
| **4625** | Security | ログオン失敗 | 高 — ブルートフォース検出 |
| 4634 | Security | ログオフ | 中 |
| **4648** | Security | 明示的クレデンシャルでのログオン（runas） | 高 |
| **4672** | Security | 特権割り当て（管理者ログオン） | 高 |
| **4768** | Security | Kerberos TGT 要求 | 高 — Golden Ticket 検出 |
| **4769** | Security | Kerberos サービスチケット要求 | 高 — Kerberoasting 検出 |
| 4771 | Security | Kerberos 事前認証失敗 | 中 |
| 4776 | Security | NTLM 認証 | 中 |

### LogonType 一覧

| Type | 名前 | 説明 | 注意点 |
|------|------|------|--------|
| 2 | Interactive | ローカルコンソールログオン | |
| 3 | Network | ネットワーク経由（SMB等） | 横展開の指標 |
| 4 | Batch | バッチジョブ | |
| 5 | Service | サービス起動 | |
| 7 | Unlock | 画面ロック解除 | |
| 8 | NetworkCleartext | 平文ネットワーク認証 | |
| 9 | NewCredentials | runas /netonly | Pass-the-Hash |
| 10 | RemoteInteractive | RDP | 横展開の指標 |
| 11 | CachedInteractive | キャッシュクレデンシャル | |

### アカウント管理

| Event ID | ログ | 説明 | SOC 重要度 |
|----------|------|------|-----------|
| **4720** | Security | ユーザーアカウント作成 | 高 |
| 4722 | Security | ユーザーアカウント有効化 | 中 |
| **4724** | Security | パスワードリセット試行 | 高 |
| **4728** | Security | グローバルグループにメンバー追加 | 高 |
| **4732** | Security | ローカルグループにメンバー追加 | 高 |
| 4756 | Security | ユニバーサルグループにメンバー追加 | 高 |
| **4740** | Security | アカウントロックアウト | 高 |

### プロセス・サービスイベント

| Event ID | ログ | 説明 | SOC 重要度 |
|----------|------|------|-----------|
| **4688** | Security | 新規プロセス作成（コマンドライン監査要） | 高 |
| 4689 | Security | プロセス終了 | 低 |
| **7045** | System | 新規サービスインストール | 高 — 持続性の指標 |
| **4697** | Security | サービスインストール | 高 |
| **4698** | Security | スケジュールタスク作成 | 高 — 持続性の指標 |

### ポリシー・システム変更

| Event ID | ログ | 説明 | SOC 重要度 |
|----------|------|------|-----------|
| 4657 | Security | レジストリ値変更 | 中 |
| 4663 | Security | オブジェクトアクセス試行 | 中 |
| 4719 | Security | 監査ポリシー変更 | 高 |
| **1102** | Security | **監査ログ消去** | **最高 — 必ずアラート** |
| **104** | System | **イベントログ消去** | **最高** |

### PowerShell ログ

| Event ID | ログ | 説明 | SOC 重要度 |
|----------|------|------|-----------|
| 4103 | PowerShell/Operational | モジュールログ | 中 |
| **4104** | PowerShell/Operational | **Script Block Logging**（スクリプト全文記録） | **最高** |
| 4105/4106 | PowerShell/Operational | Script Block 開始/終了 | 低 |

## Sysmon イベント

| Event ID | 説明 | SOC 重要度 |
|----------|------|-----------|
| **1** | **プロセス作成**（ハッシュ、親プロセス含む、4688 より優秀） | **最高** |
| 2 | ファイル作成時刻変更（Timestomp） | 高 |
| **3** | **ネットワーク接続** | **高** |
| 5 | プロセス終了 | 低 |
| 6 | ドライバロード | 中 |
| **7** | **イメージロード（DLL）** | **高** |
| **8** | **CreateRemoteThread**（インジェクション指標） | **最高** |
| 9 | RawAccessRead | 中 |
| **10** | **プロセスアクセス**（LSASS クレデンシャルダンプ検出） | **最高** |
| **11** | **ファイル作成** | **高** |
| **12/13/14** | **レジストリイベント**（キー作成/値設定/リネーム） | **高** |
| 15 | FileCreateStreamHash（ADS） | 中 |
| 17/18 | パイプ作成/接続 | 中 |
| 19/20/21 | WMI イベントフィルタ/コンシューマ/バインディング | 高 |
| **22** | **DNS クエリ** | **高** |
| **23** | **ファイル削除（アーカイブ付き）** | **高** |
| 25 | プロセス改ざん | 高 |

## 攻撃フェーズ別ログインジケータ

### Reconnaissance（偵察）
- 複数アカウントへの連続ログオン失敗（4625）→ Password Spraying
- 異常な LDAP クエリ → AD 列挙（BloodHound/SharpHound）
- FW ログでのポートスキャンパターン
- 内部ドメインへの過剰な DNS クエリ

### Initial Access（初期アクセス）
- 異常な地理的位置からのログオン / Impossible Travel
- 新しい User-Agent やデバイスからのログオン
- フィッシングメール配信後の Office プロセスからの cmd.exe / PowerShell 生成
- 匿名化サービス（Tor、VPN プロバイダ）からの VPN アクセス

### Execution（実行）
- **PowerShell エンコードコマンド**: `-enc`, `-encodedcommand`
- **LOLBins**: mshta.exe, regsvr32.exe, rundll32.exe の不審な実行
- **Office → cmd → PowerShell チェーン**: winword.exe → cmd.exe → powershell.exe
- **WMIC プロセス作成**

### Persistence（持続性）
- **新規スケジュールタスク**: Event ID 4698、変更ウィンドウ外
- **新規サービス**: Event ID 7045 / 4697
- **新規ユーザーアカウント**: Event ID 4720、変更ウィンドウ外
- **レジストリ Run Key**: Sysmon 12/13
- **WMI イベントサブスクリプション**: Sysmon 19/20/21
- **Startup フォルダ変更**

### Privilege Escalation（権限昇格）
- **LSASS アクセス**: Sysmon 10（TargetImage: lsass.exe）→ クレデンシャルダンプ
- **UAC バイパスパターン**: eventvwr.exe, fodhelper.exe の悪用
- **サービスアカウントの異常使用**
- **トークン操作イベント**

### Lateral Movement（横展開）
- **Type 3 ログオン**: 4624 LogonType 3（異常なソースから）
- **Type 10 ログオン**: 4624 LogonType 10（ワークステーション間 RDP）
- **PsExec パターン**: 7045 に PSEXESVC サービス
- **SMB 管理共有アクセス**: C$, ADMIN$（Event ID 5140/5145）
- **Pass-the-Hash**: 4624 + NTLM + LogonType 9 or 3（予期しないソース）

### Defense Evasion（防御回避）
- **監査ログ消去**: 1102, 104 — **最も重要なインジケータ**
- **プロセスインジェクション**: Sysmon 8（CreateRemoteThread、非標準プロセスへ）
- **セキュリティツール無効化**: サービス停止、改ざん保護イベント
- **Timestomp**: ファイル作成時刻の不一致

### Command and Control（C2）
- **ビーコンパターン**: 同一ドメイン/IP への定期接続
- **JA3/JA3S フィンガープリント**: 既知 C2 フレームワーク（Cobalt Strike、Metasploit）
- **DNS over HTTPS**: 非標準リゾルバへの DoH
- **ドメインフロンティング**
- **新規登録ドメイン（NRD）への接続**
- **異常な User-Agent / Cookie パターン**

### Exfiltration（流出）
- **異常データ量**: プロキシ/FW ログで検出
- **DNS トンネリング**: 単一ドメインへの大量 DNS クエリ、長いサブドメイン、TXT レコード
- **クラウドストレージサービスへの大量アップロード**: Mega、Dropbox、Google Drive
- **暗号化トラフィックの異常な宛先**

### Impact（影響）
- **大量ファイルリネーム/暗号化**: ランサムウェア
- **VSS シャドウコピー削除**: `vssadmin delete shadows`
- **BCDEdit 復旧無効化**: `bcdedit /set {default} recoveryenabled No`
- **バックアップカタログ削除**: `wbadmin delete catalog`
