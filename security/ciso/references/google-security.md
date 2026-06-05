# Google Security プラットフォーム リファレンス

## Google Security Command Center（SCC）

### ティア比較

| 機能 | Standard | Premium | Enterprise |
|------|----------|---------|------------|
| Security Health Analytics | 限定的 | 全機能 | 全機能 |
| Event Threat Detection | - | ○ | ○ |
| Container Threat Detection | - | ○ | ○ |
| VM Threat Detection | - | ○ | ○ |
| Cloud Run Threat Detection | - | ○ | ○ |
| Web Security Scanner | - | ○ | ○ |
| 攻撃パスシミュレーション | - | ○ | ○ |
| Toxic Combinations | - | ○ | ○ |
| コンプライアンス監視 | 限定的 | ○ | ○ |
| マルチクラウド（AWS/Azure） | - | - | ○ |
| Chronicle SOAR 統合 | - | - | ○ |
| Gemini AI 調査支援 | - | - | ○ |
| 有効化レベル | Org | Org/Project | Org |

### 検出サービス

**Security Health Analytics**
- クラウドリソースの設定ミスを継続スキャン
- CIS、PCI DSS、NIST、ISO 27001 のコントロールにマッピング
- カスタムモジュールで組織固有の検出ロジック追加可能

**Event Threat Detection（ETD）**
- Cloud Logging と Google Workspace ログをニアリアルタイムで監視
- 検出手法: 検出ロジック、脅威インテリジェンス、トリップワイヤー、プロファイリング、ML、異常検出
- MITRE ATT&CK にマッピングされた検出カテゴリ
- ログソース: Cloud Audit Logs、Cloud DNS、Cloud IDS、Google Workspace、Agent Engine
- 主要検出器: Log4j スキャン、SSH ブルートフォース、BigQuery データ流出、Cloud SQL 不正エクスポート、VPC SC 回避、IAM 異常

**Container Threat Detection（CTD）**
- GKE の Container-Optimized OS ノードのランタイム攻撃を継続監視
- カーネルレベルの行動収集 + NLP（Bash/Python）でのスクリプト分析
- 40+ 検出器: クレデンシャルアクセス、防御回避、実行、流出、C2、持続性
- 検出例: GPG キー偵察、秘密鍵検索、Base64 スクリプト、コンテナエスケープ、K8s 攻撃ツール

**Virtual Machine Threat Detection（VMTD）**
- **エージェントレス**: ハイパーバイザーレベルからのメモリスキャン（業界初）
- 暗号通貨マイニング、カーネルモードルートキット、ブートキット、マルウェアを検出
- ゲスト VM への性能影響なし、攻撃者から不可視

### 攻撃パスシミュレーション
- 約6時間ごとに実行（最低1日1回）
- クラウドリソース、設定、IAM、ネットワーク接続のグラフを構築
- パブリックインターネットから高価値リソースへの仮想攻撃パスをシミュレート
- 24 リソースタイプをサポート
- **Attack Exposure Score**: リソースに 0-10 のスコア
- 計算要素: 優先度値（HIGH=10, MED=5, LOW=1）、攻撃パス数、成功シミュレーション率

### Toxic Combinations と Chokepoints
- **Toxic Combinations**: 複合的なセキュリティ問題が高価値リソースへの攻撃パスを形成
- 重大度: Critical（スコア >= 10）、High（スコア < 10）
- **Chokepoints**: 複数の攻撃パスが収束するリソース。修正すると複数の Toxic Combinations を同時解消
- Enterprise ティア: Chronicle SOAR で自動ケース作成、修正検出時に自動クローズ

### コンプライアンス監視
- 対応基準: CIS Google Cloud Foundations Benchmark（v2.0.0）、PCI DSS、NIST 800-53、ISO 27001、HIPAA
- 通過/不合格コントロールのダッシュボード、改善手順付き
- 監査チーム向けエクスポート機能

### セキュリティポスチャ管理
- ベンチマークに対するクラウド資産のセキュリティ状態を定義・管理
- 13 の事前定義ポスチャテンプレート（Secure by Default、Secure AI、CIS 2.0、NIST 等）
- **ドリフト検出**: 未承認変更の継続監視
- Org/Folder/Project レベルでデプロイ

### SCC API と自動化
- REST API: Findings の作成/一覧/更新、状態変更、Security Marks
- Pub/Sub への連続エクスポートで外部連携
- Cloud Run Functions による自動修正ワークフロー

### SCC 運用ベストプラクティス
1. 全検出サービスを有効化して最新に保つ
2. 高価値リソースセットを定義して Attack Exposure Score を優先
3. 動的ミュートルール（静的ではなく）で既知の許容 Finding を抑制
4. Mandiant CVE インテリジェンスで脆弱性を優先順位付け
5. ニアリアルタイムアラートの通知チャネルを設定
6. Pub/Sub 連続エクスポートで下流システムと統合
7. Data Access Audit Logs と Google Workspace Logs をデフォルト以上に有効化

## Google Security Operations（旧 Chronicle）

### SIEM 機能
- Google インフラ上のクラウドネイティブ SIEM
- **12ヶ月のホットデータ保持**（即時検索可能）
- 800+ パーサーによるログ正規化
- 300+ SOAR 統合
- 検出エンジン: 単一イベントルール、マルチイベントルール、複合検出ルール
- ルール制限: Standard 1,000 単一イベント + 75 マルチイベント / 上位ティア 2,000 + 125
- Applied Threat Intelligence によるキュレート検出ルール
- 2025 Gartner Magic Quadrant SIEM 部門リーダー

### SOAR 機能
- ドラッグ＆ドロップのビジュアルプレイブックビルダー
- 300+ ツール統合
- **AI 生成プレイブック**: Gemini による自動プレイブック作成
- ケース管理: 関連アラートのグループ化、割り当て、コラボレーション
- Tier-1 タスク自動化で最大 **98% の対応時間削減**
- 事前構築ユースケース（フィッシング、ランサムウェア等）

### UDM（Unified Data Model）

数千フィールドで多様なイベントタイプを記述・分類するフレームワーク。

**主要イベントタイプ:**
- `NETWORK_CONNECTION`, `NETWORK_HTTP`, `NETWORK_DNS`
- `PROCESS_LAUNCH`, `PROCESS_OPEN`
- `FILE_CREATION`, `FILE_MODIFICATION`
- `USER_LOGIN`, `USER_CREATION`

**イベント構造:**
- `metadata`: いつ/タイプ/ソース
- `principal`: ソースエンティティ
- `target`: 宛先エンティティ
- `src`: 送信元情報
- `observer`: 観察者情報
- `network`: ネットワーク情報
- `security_result`: セキュリティ製品の分類/アクション

### YARA-L 2.0 検出ルール

詳細は [detection-engineering.md](detection-engineering.md) の YARA-L 2.0 セクションを参照。

### Entity Graph とコンテキスト強化
- Entity Context Graph（ECG）: UDM イベントデータとコンテキスト強化データの関係グラフ
- 関係モデル:「ユーザー X が資産 Y を所有し、リソース Z にアクセス可能」
- 強化ソース: Google Safe Browsing、リモートアクセスデータ、OSINT

### 脅威インテリジェンス統合
- **Google Threat Intelligence（GTI）**: VirusTotal + Mandiant + Google Threat Insights
- 受信テレメトリに対する既知インジケータの自動スキャン
- Applied Threat Intelligence: GTI スコアリングとキュレート検出ルール
- GTI データ（Threat Lists、IoC Streams、アドバーサリコンテキスト）の自動取り込み

### ログインジェスト
- 600-800+ サポートログタイプ
- パーサーが Raw ログ（JSON、Syslog、CSV、非構造化テキスト）を UDM に正規化
- セルフサービスパーサー: 自動抽出（JSON/XML 推奨）、カスタムパーサー作成
- Health Hub: データソースの状態と健全性の一元監視
- インジェスト方法: Forwarder（syslog、PCAP）、Collector、Ingestion API、クラウド API 接続

### 検索と調査
- **UDM Search**: YARA-L 2.0 構文で正規化イベントとアラートを検索
- **Raw Log Search**: `raw = "検索文字列"` で Raw ログを検索、UDM イベントと相関
- 調査ビュー: 資産、IP アドレス、ハッシュ、ドメイン、ユーザー影響
- Prevalence グラフ: 期間ごとの接続パターン

### Gemini in Security Operations
- **自然言語クエリ**: 自然言語で検索ステートメントを入力 → UDM 検索クエリを生成
- **AI 支援調査**: インタラクティブチャットアシスタント
- **検出ルール生成**: 自然言語から YARA-L 2.0 ルールを作成
- **プレイブック作成**: 自然言語から SOAR プレイブックを生成
- **推奨対応アクション**: AI による修正ガイダンス

### Agentic SOC（2025-2026）
- **Alert Triage and Investigation Agent（TIN）**: AI エージェントがアラートを自律的に調査
- 証拠収集、分析（スクリプト難読化解除含む）、シグナル相関を自動実行
- Human-in-the-loop: AI が大量トリアージを処理、アナリストは戦略的判断に集中
- **MCP（Model Context Protocol）**: マルチベンダーツール接続

### Chronicle API
- REST API: Cases、検出ルール、イベント、エンティティ、IOC、参照リスト、パーサー、コネクタ
- UDM 検索エンドポイント
- Ingestion API（直接ログ送信）
- RBAC API

## SCC と Security Operations の連携

### End-to-End パイプライン

```
検出                    強化                    調査                    対応
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│ SCC:         │    │ Chronicle:  │    │ 統合調査:    │    │ SOAR:       │
│ 設定ミス検出  │ → │ ログイベント │ → │ Entity Graph │ → │ プレイブック │
│ 脆弱性検出   │    │ と相関      │    │ + Gemini AI  │    │ 自動対応    │
│ 脅威検出     │    │ + GTI 強化  │    │              │    │             │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
```

### データフロー
- **SCC Enterprise**: Findings が自動的に Chronicle SIEM に取り込まれる。Critical な Findings（Toxic Combinations）は自動的に SOAR ケース作成
- **SCC Standard/Premium**: Pub/Sub への Continuous Export → Chronicle SIEM/SOAR に転送
- Chronicle に SCC Findings 専用のログタイプとパーサーあり
- SCC 脅威検出向けの事前構築 Chronicle ルール

### 自動対応ワークフロー
- SOAR の Out-of-box プレイブックで SCC データを処理
- Findings → 自動強化 → 調査 → 修正のプレイブックオーケストレーション
- Toxic Combination Findings → 自動ケース作成 → Risk Engine が修正検出 → 自動クローズ

## Google Threat Intelligence（GTI）

### 統合プラットフォーム
- **VirusTotal**: ファイル/URL/ドメイン/IP 分析、マルウェアリポジトリ
- **Mandiant Threat Intelligence**: 最前線 IR から得た脅威インテリジェンス
- **Google Threat Insights**: Google の可視性（Gmail、Chrome、Android）からの脅威データ
- **Mandiant Digital Threat Monitoring**: ダークウェブ監視
- **Mandiant Attack Surface Management**: 外部攻撃面管理

### Chronicle との統合
- GTI データが自動的に Chronicle に取り込まれる
- Applied Threat Intelligence によるスコアリングとキュレート検出ルール
- YARA-L ルールによる受信テレメトリの既知インジケータ自動スキャン
- 調査時の脅威コンテキスト強化

## 主要ドキュメント URL

### SCC
- サービスティア: https://docs.google.com/security-command-center/docs/service-tiers
- 検出サービス: https://docs.google.com/security-command-center/docs/concepts-security-sources
- ETD 概要: https://docs.google.com/security-command-center/docs/concepts-event-threat-detection-overview
- 攻撃パス: https://docs.google.com/security-command-center/docs/attack-exposure-learn
- Toxic Combinations: https://docs.google.com/security-command-center/docs/toxic-combinations-overview
- ベストプラクティス: https://cloud.google.com/security-command-center/docs/optimize-security-command-center

### Security Operations
- プラットフォーム概要: https://docs.google.com/chronicle/docs/secops/understand-the-secops-platform
- YARA-L 2.0 構文: https://docs.google.com/chronicle/docs/detection/yara-l-2-0-syntax
- UDM 概要: https://cloud.google.com/chronicle/docs/event-processing/udm-overview
- UDM フィールド一覧: https://cloud.google.com/chronicle/docs/reference/udm-field-list
- サポートログタイプ: https://docs.google.com/chronicle/docs/ingestion/parser-list/supported-default-parsers
- Gemini: https://docs.google.com/chronicle/docs/secops/gemini-chronicle
- 検出ルールリポジトリ: https://github.com/chronicle/detection-rules
- Agentic SOC: https://cloud.google.com/solutions/security/agentic-soc
