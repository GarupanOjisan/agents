# 検出エンジニアリング リファレンス

## Pyramid of Pain（David Bianco, 2013）

検出指標の価値を示すモデル。上位ほど攻撃者が変更困難。

```
          /\
         /  \     TTPs（戦術・技術・手順）
        /    \    ← 最も困難: 攻撃者は根本的な行動変更が必要
       /------\
      / Tools  \  ← 困難: リツーリングは高コスト
     /----------\
    / Network/   \  ← 煩わしい: C2ドメイン、インフラIP
   / Host Artifacts\  ← 不便: レジストリキー、Mutex名
  /----------------\
 / Domain Names     \  ← 簡単: DGA、Fast-flux で緩和
/--------------------\
/ Hash Values         \  ← 些末: 1ビット変更で新ハッシュ
/______________________\
```

**検出エンジニアリングの原則**: ピラミッド上位（TTP・Tools）での検出を優先する。行動検出は IOC ベースの検出より遥かに耐久性が高い。

## Sigma ルール

### 概要
プラットフォーム非依存の汎用 SIEM 検出ルールフォーマット（YAML ベース）。

### ルール構造

```yaml
title: Suspicious PowerShell Encoded Command
id: <UUID>
status: experimental|test|stable
description: Detects suspicious encoded PowerShell command execution
references:
    - https://attack.mitre.org/techniques/T1059/001/
author: Author Name
date: 2024/01/15
tags:
    - attack.execution
    - attack.t1059.001
logsource:
    category: process_creation
    product: windows
detection:
    selection:
        Image|endswith: '\powershell.exe'
        CommandLine|contains:
            - '-enc'
            - '-encodedcommand'
    condition: selection
falsepositives:
    - Legitimate admin scripts
level: medium
```

### 主要修飾子
`|contains`, `|endswith`, `|startswith`, `|re`（正規表現）, `|base64`, `|cidr`

### 変換ツール
- **pySigma**（新世代）: Sigma ルールを各 SIEM クエリに変換
- 対応: SPL（Splunk）、KQL（Sentinel）、Lucene（Elastic）、AQL（QRadar）、YARA-L（Chronicle）等

### リソース
- SigmaHQ: https://github.com/SigmaHQ/sigma （3000+ ルール）

## YARA ルール

### 概要
マルウェアの識別・分類に使用するパターンマッチングツール。

### ルール構造

```yara
rule APT_Malware_Example
{
    meta:
        author = "Analyst Name"
        description = "Detects Example APT malware variant"
        date = "2024-01-15"
        hash = "abc123..."
        mitre_att_ck = "T1059"

    strings:
        $mz = "MZ"
        $s1 = "malicious_string" ascii wide
        $s2 = { 48 8B 05 ?? ?? ?? ?? 48 89 44 24 }  // hex + wildcard
        $s3 = /https?:\/\/[a-z0-9]+\.evil\.com/       // regex

    condition:
        $mz at 0 and (2 of ($s*))
}
```

### 用途
- マルウェアリポジトリでの検索（VirusTotal）
- エンドポイントでの脅威ハンティング
- サンドボックスでのファイルスキャン
- IR ツールとの統合

### 主要機能
- 文字列マッチング（ASCII、Wide、Hex、Regex）
- 論理条件式
- ファイルメタデータ（filesize、entry point、PE imports）
- モジュール: PE, ELF, Math, Hash, Dotnet

## YARA-L 2.0（Google Security Operations）

### 概要
Google Security Operations（Chronicle）固有の検出ルール言語。UDM イベントに対して動作する。

### ルール構造

```
rule entra_id_brute_force_attempt {
  meta:
    author = "SOC Team"
    description = "Detects brute force login attempts from Entra ID"
    rule_id = "mr_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    rule_name = "Entra ID Brute Force Attempt"
    severity = "High"
    priority = "High"
    tactic = "Credential Access"
    technique = "T1110"

  events:
    $login.metadata.event_type = "USER_LOGIN"
    $login.metadata.vendor_name = "Microsoft"
    $login.security_result.action = "BLOCK"
    $login.target.user.userid = $user

  match:
    $user over 10m

  outcome:
    $risk_score = 85
    $event_count = count($login.metadata.id)
    $target_user = array_distinct($login.target.user.userid)

  condition:
    #login >= 10
}
```

### スタイルガイドベストプラクティス
- ファイル拡張子: `.yaral`
- `rule_id`: UUIDv4 に `mr_` プレフィックス
- 重大度とリスクスコアの対応: Info=10, Low=35, Medium=65, High=85, Critical=95
- 変数名: 記述的、アンダースコア区切り（`$target_process_command_line`）
- パフォーマンス: event type フィルタを最初に、等値比較を正規表現より前に
- `match` 変数は自動的に NULL を除外（冗長な null チェック不要）
- ルールタイプ: `alert`（高信頼度）vs `hunt`（探索的）

### リソース
- 公式ルールリポジトリ: https://github.com/chronicle/detection-rules
- スタイルガイド: https://github.com/chronicle/detection-rules/blob/main/STYLE_GUIDE.md

## Snort / Suricata ルール

### 概要
ネットワーク侵入検知/防御システム（IDS/IPS）のルール。

### Snort ルール構造

```
alert tcp $EXTERNAL_NET any -> $HOME_NET 445 (
    msg:"ET EXPLOIT Possible EternalBlue Attempt";
    flow:to_server,established;
    content:"|ff|SMB";
    content:"|23 00 00 00 07 00|";
    distance:0;
    within:6;
    reference:cve,2017-0144;
    classtype:attempted-admin;
    sid:2024123;
    rev:1;
)
```

### Suricata の Snort に対する優位性
- マルチスレッドアーキテクチャ（高スループット）
- ネイティブプロトコルパーシング（HTTP, DNS, TLS, SMB）
- Lua スクリプティング
- EVE JSON ログ（構造化出力）
- JA3/JA3S TLS フィンガープリント
- ファイル抽出機能

### ルールセット
- **Emerging Threats Open**（無償）/ **ET Pro**（有償）: 最も広く使用されるルールセット

## Detection-as-Code

### 原則
1. **バージョン管理**: 全検出ルールを Git で管理
2. **コードレビュー**: PR/MR プロセスで検出ルールをレビュー
3. **テスト**: 真陽性検証、偽陽性テストのユニットテスト
4. **CI/CD**: 検出ルールの本番 SIEM への自動デプロイ
5. **ドキュメント**: ルールにコンテキスト、参照、対応手順を含める
6. **メトリクス**: 検出ルールの性能追跡（真陽性率、偽陽性率）

### 典型的パイプライン

```
ルール作成 → Git コミット → CI バリデーション → コードレビュー →
サンプルデータでテスト → ステージングにデプロイ → 検証 →
本番デプロイ → パフォーマンス監視 → 反復改善
```

### ベストプラクティス
- 全ルールを MITRE ATT&CK テクニックにマッピング
- 重大度、信頼度、リスクスコアを含める
- 期待される真陽性と既知の偽陽性を文書化
- 対応プレイブックへの参照を含める
- ATT&CK ヒートマップでカバレッジギャップを追跡

### テストツール
- **Atomic Red Team**: テクニック単位の攻撃シミュレーション
- **MITRE CALDERA**: 自動敵対者エミュレーション
- **Detection Lab**: 検出ルールのテスト環境

## Palo Alto Networks 検出機能

### BIOC ルール（Behavioral Indicators of Compromise）
- Cortex XDR のカスタム検出ルール
- イベントシーケンスに基づく行動検出
- MITRE ATT&CK テクニックにマッピング
- 例:「プロセスAがプロセスBを生成し、非標準ポートへの外部接続を実行」

### XQL（XDR Query Language）
- Cortex XDR/XSIAM のクエリ言語
- SQL ライクな構文
- 脅威ハンティング、カスタム検出ルール、アドホック調査に使用

### WildFire
- クラウドベースのマルウェア分析・サンドボックス
- 静的分析、動的分析、ML 分類、ベアメタル分析
- 判定: Benign / Malware / Grayware / Phishing
- 新脅威検出時に自動的にシグネチャを全 PAN 製品に配布

## CrowdStrike 検出機能

### IOA（Indicators of Attack）
- CrowdStrike Falcon の行動ベース検出
- IOC（事後指標）ではなく攻撃行動をリアルタイム検出
- Threat Graph（クラウドベースのグラフDB）で相関分析

### Falcon LogScale（旧 Humio）
- 高速ログ管理・検索
- リアルタイムログインジェストと検索
