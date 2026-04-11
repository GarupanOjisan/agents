# 脅威インテリジェンス リファレンス

## 脅威アクター命名規則

### Mandiant 分類体系

| 接頭辞 | 意味 | 例 |
|--------|------|-----|
| **APT** | 国家支援の高度持続的脅威（帰属確定） | APT1, APT28, APT29, APT41 |
| **FIN** | 金銭目的の脅威グループ | FIN6, FIN7, FIN11, FIN12 |
| **UNC** | 未分類/未帰属のクラスター | UNC2452, UNC3886, UNC5537 |

UNC は十分な証拠が揃うと APT または FIN に昇格する。

### CrowdStrike 命名規則（動物名）

| 動物 | 帰属国 |
|------|--------|
| **BEAR** | ロシア（FANCY BEAR=APT28, COZY BEAR=APT29, VOODOO BEAR=Sandworm） |
| **PANDA** | 中国（WICKED PANDA=APT41, MUSTANG PANDA, GOBLIN PANDA） |
| **KITTEN** | イラン（CHARMING KITTEN=APT35, REMIX KITTEN） |
| **CHOLLIMA** | 北朝鮮（LABYRINTH CHOLLIMA=Lazarus） |
| **SPIDER** | サイバー犯罪（WIZARD SPIDER=Conti, SCATTERED SPIDER） |
| **JACKAL** | ハクティビスト |
| **BUFFALO** | ベトナム |
| **LEOPARD** | パキスタン |
| **TIGER** | インド |
| **WOLF** | トルコ |

### Microsoft 命名規則（天候ベース、2023年〜）

| 天候現象 | 帰属国 |
|---------|--------|
| Blizzard | ロシア（Midnight Blizzard=APT29） |
| Typhoon | 中国 |
| Sandstorm | イラン |
| Sleet | 北朝鮮 |
| Tempest | サイバー犯罪 |

## 主要 APT グループ

### ロシア

**APT28（Fancy Bear / Sofacy）** — GRU Unit 26165
- 標的: NATO政府機関、防衛、メディア、政治組織
- TTP: スピアフィッシング、ゼロデイ、クレデンシャルハーベスティング
- 主要作戦: DNC ハック（2016）、ドイツ連邦議会（2015）

**APT29（Cozy Bear / NOBELIUM）** — SVR
- 標的: 政府、シンクタンク、ヘルスケア、テクノロジー
- TTP: サプライチェーン攻撃、クラウドサービスを C2 に利用
- 主要作戦: SolarWinds（2020）、COVID-19 ワクチン研究標的

**APT44（Sandworm / Voodoo Bear）** — GRU Unit 74455
- 世界で最も破壊的なサイバー脅威アクター
- 主要作戦: ウクライナ電力網攻撃（2015,2016）、NotPetya（2017）、Olympic Destroyer（2018）

### 中国

**APT41（Double Dragon / Wicked Panda）**
- 国家スパイと金銭目的の二重活動
- 標的: ヘルスケア、テレコム、テクノロジー、ゲーム、金融
- TTP: サプライチェーン攻撃、ルートキット、カスタムマルウェア

**APT40** — MSS（海南省）
- 標的: 海洋、防衛、航空、テクノロジー
- TTP: Web サーバー脆弱性悪用、カスタムバックドア

**UNC3886** — 中国関連
- VMware ESXi とネットワークインフラをゼロデイで標的

### 北朝鮮

**APT43（Kimsuky）** — RGB
- 標的: 政府、核政策、シンクタンク、暗号通貨
- TTP: ソーシャルエンジニアリング、クレデンシャル窃取

**APT38 / Lazarus Group**
- 標的: 金融機関、暗号通貨取引所
- 主要作戦: バングラデシュ中央銀行（2016）、WannaCry

### イラン

**APT35（Charming Kitten / Magic Hound）** — IRGC
- 標的: 反体制派、学術界、政府
- TTP: スピアフィッシング、クレデンシャルハーベスティング

**APT34（OilRig）** — MOIS
- 標的: 中東の政府、エネルギー
- TTP: DNS トンネリング、カスタムバックドア

## 金銭目的グループ（FIN）

| グループ | 概要 |
|---------|------|
| FIN6 | 決済カード窃取 → ランサムウェア（Ryuk） |
| FIN7（Carbanak） | 最も多産な金融犯罪グループ、ランサムウェアに進化 |
| FIN11 | 大規模悪用キャンペーン、Clop ランサムウェア（MOVEit、Accellion FTA） |
| FIN12 | ランサムウェア特化、侵入からランサムウェアまで2日未満 |

## ランサムウェアエコシステム

### 主要 RaaS（Ransomware as a Service）

- **LockBit**: 最も活発な RaaS オペレーション
- **BlackCat/ALPHV**: Rust 製ランサムウェア、Triple Extortion
- **Clop/Cl0p**: 大規模脆弱性悪用（MOVEit、GoAnywhere）
- **Black Basta**: 元 Conti メンバーの派生
- **Royal/BlackSuit**: 高額身代金要求

### 最近のトレンド（M-Trends / Unit 42）
- 二重・三重恐喝の標準化
- 暗号化なしのデータ窃取のみの攻撃
- 初期アクセスブローカー（IAB）エコシステムの成長
- エッジデバイス（VPN、ファイアウォール）のゼロデイ悪用の増加

## Mandiant M-Trends 主要指標

### グローバル中央値 滞留時間（Dwell Time）

| 年 | 日数 |
|----|------|
| 2015 | 146日 |
| 2018 | 78日 |
| 2020 | 24日 |
| 2022 | 16日 |
| 2023 | 10日 |

### 初期アクセスベクター（最近の傾向）
1. 脆弱性悪用（~38%） — 最多
2. フィッシング（~17%）
3. 窃取クレデンシャル（~15%）

### 検出ソース
- 内部検出が増加傾向（~54%）
- ランサムウェアは「自己通知型」（身代金要求メモ = 検出）

### 最も標的となる業界
1. 金融サービス
2. ビジネス/プロフェッショナルサービス
3. テクノロジー
4. 政府
5. ヘルスケア

## Unit 42 脅威インテリジェンス

### 主要レポート
- **Ransomware and Extortion Report**（年次）: ランサムウェア動向、身代金統計
- **Cloud Threat Report**（半期）: クラウドセキュリティリスク、設定ミス統計
- **Threat Briefs**: 緊急脆弱性への迅速対応（Log4Shell、MOVEit、Citrix Bleed 等）

### Unit 42 追跡脅威グループ例
- Muddled Libra（Scattered Spider と重複）
- Sofacy（APT28）
- OilRig（APT34）
- Lazarus Group

## CrowdStrike 脅威インテリジェンス

### 主要レポート
- **Global Threat Report**（年次）: 脅威ランドスケープ全体像
- **OverWatch Threat Hunting Report**（年次）: 脅威ハンティングトレンド
- **eCrime Index（ECX）**: eCrime エコシステムの健全性追跡

### 最近のトレンド
- アイデンティティベース攻撃の急増
- クラウド悪用の増加
- AI を活用したソーシャルエンジニアリング
- 平均ブレイクアウト時間: 62分未満
- 1-10-60 ルール: 1分で検出、10分で調査、60分で封じ込め

## Google Threat Intelligence（GTI）

- VirusTotal + Mandiant + Google Threat Insights の統合プラットフォーム
- Google TAG（Threat Analysis Group）/ GTIG の研究
- 主要レポート:
  - M-Trends（年次）
  - Cloud Threat Horizons（半期）
  - Cybersecurity Forecast（年次）
  - Zero-Day Review（年次）
  - AI Threat Tracker

### 最近の重要な知見
- 脆弱性公開から悪用までの期間が数週間から数日に短縮
- ソフトウェア脆弱性悪用（44.5%）が弱いクレデンシャル（27.2%）を初期アクセスで上回る
- PROMPTFLUX/PROMPTSTEAL: 実行中に LLM にクエリして回避するマルウェア
- エッジ/コアネットワークデバイス（VPN、ルーター）への標的化が増加

## 年次レポートカレンダー

| レポート | 発行元 | 概要 |
|---------|--------|------|
| M-Trends | Mandiant/Google | 滞留時間、攻撃ベクター、業界別動向 |
| Global Threat Report | CrowdStrike | 脅威アクター、ブレイクアウト時間 |
| Ransomware Threat Report | Unit 42 | ランサムウェア動向、身代金統計 |
| DBIR | Verizon | 最も広く参照されるデータ侵害レポート |
| Cost of a Data Breach | IBM | 侵害の財務的影響 |
| Threat Detection Report | Red Canary | 最も多く観測される ATT&CK テクニック |
| Cloud Threat Report | Unit 42 | クラウド固有のリスクと攻撃 |
