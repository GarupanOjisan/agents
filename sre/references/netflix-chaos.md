# Netflix 信頼性エンジニアリングとカオスエンジニアリング

Source references:
- Netflix Chaos Monkey: https://github.com/Netflix/chaosmonkey
- Netflix / Google Kayenta automated canary analysis: https://www.engineering.fyi/article/automated-canary-analysis-at-netflix-with-kayenta
- Principles of Chaos Engineering: https://principlesofchaos.org/

Use this reference for chaos experiments, failure injection, canary analysis, resilience validation, and release safety.

## Experiment Contract

Never run or recommend a chaos experiment without this contract:

```markdown
## Experiment Contract
- Hypothesis:
- Steady-state metric:
- Target system:
- Fault injection:
- Blast radius:
- Abort / kill switch:
- Observation window:
- Success criteria:
- Failure criteria:
- Rollback:
- Owner:
```

## Safety Gates

- The protected user journey and SLO are known.
- A steady-state metric is business/user-visible, not only infrastructure health.
- Blast radius is intentionally bounded.
- Abort conditions are automatic where possible.
- On-call and stakeholders know the schedule.
- Rollback or traffic shift is ready before injection.
- The experiment records results and creates follow-up actions.

## Automated Canary Analysis Contract

For canary or progressive delivery:

- Define baseline and canary populations.
- Compare critical, high, and informational metrics separately.
- Critical metrics failing should fail the canary regardless of aggregate score.
- Include rollback criteria and post-rollback validation.
- Prefer automated judgement for repeated releases, with human review for ambiguous high-impact launches.

## 1. カオスエンジニアリングの5原則

> カオスエンジニアリングとは、本番環境における分散システムの信頼性に対する確信を高めるために、システムに対して実験的な障害を注入する規律ある手法。

### 原則1: 定常状態の仮説を立てる
- システムの「正常」をビジネスメトリクスで定義（SPS、エラー率、レイテンシ P99）
- 仮説例:「サービスのインスタンスが1台停止しても、SPS は 0.1% 以上低下しない」

### 原則2: 実世界の事象を多様に変化させる
- サーバー障害、ネットワーク分断、レイテンシ増大、DNS障害、リージョン全体ダウン
- 依存外部サービスの障害、トラフィックスパイク

### 原則3: 本番環境で実験を行う
- ステージングではトラフィックパターンやデータ分布が異なるため不十分
- 段階的に進め、十分な準備ができてから本番に移行

### 原則4: 実験を継続的に自動化する
- システムは常に変化するため、CI/CD の一部として自動実行

### 原則5: 爆発半径を最小化する
- 少数のユーザーのみに影響を限定
- 異常検知時の自動停止機構（kill switch）を備える

---

## 2. カオスツール群

### Chaos Monkey
- 本番環境でランダムにインスタンスを終了
- 営業時間中のみ実行
- 単一インスタンス障害への耐性を強制する設計原則

### Simian Army

| ツール | 機能 |
|--------|------|
| Chaos Monkey | インスタンス終了 |
| Chaos Gorilla | AZ 全体を無効化 |
| Chaos Kong | リージョン全体を無効化 |
| Latency Monkey | レイテンシ注入 |
| Conformity Monkey | ベストプラクティス違反検出 |
| Security Monkey | セキュリティ設定違反検出 |

### FIT（Failure Injection Testing）
- 特定のサービス間通信に精密に障害を注入
- 影響トラフィックの割合を制御
- データストア障害もシミュレート

### ChAP（Chaos Automation Platform）
- A/B テスト手法で統計的に影響を評価
- コントロール群とエクスペリメント群にトラフィック分割
- 有意差検出で自動判定、爆発半径を自動制御

---

## 3. レジリエンスパターン

### サーキットブレーカー（Hystrix の概念）

```
[CLOSED] ←─ 成功率回復 ── [HALF-OPEN]
    │                         ↑
    │ 失敗率が閾値超過     テスト通信
    ↓                         │
[OPEN] ──── タイムアウト後 → [HALF-OPEN]
```

**主要パラメータ:**
| パラメータ | 説明 | 典型的な値 |
|-----------|------|-----------|
| requestVolumeThreshold | 判定最小リクエスト数 | 20 |
| errorThresholdPercentage | オープン閾値 | 50% |
| sleepWindowInMilliseconds | OPEN→HALF-OPEN 待機 | 5000ms |
| timeout | コマンド実行タイムアウト | 1000ms |

### バルクヘッドパターン

各依存サービスへの呼び出しに専用リソースを割り当て、障害伝播を防止。

```
[メインスレッドプール]
  ├── [サービスB用: 10スレッド]
  ├── [サービスC用: 15スレッド]
  └── [サービスD用: 5スレッド]
```

### フォールバック戦略

| 戦略 | 使用例 |
|------|--------|
| キャッシュフォールバック | パーソナライズ失敗 → キャッシュ結果 |
| 静的フォールバック | プロフィール取得失敗 → デフォルト値 |
| 機能縮退 | パーソナライズ失敗 → 汎用トップ10 |
| 代替サービス | プライマリDB障害 → レプリカDB |
| サイレント失敗 | ログ収集障害 → ログドロップ |

**設計原則:**
- Critical Path と Non-Critical Path を明確に区別
- 「何も表示されない」より「多少パーソナライズされていないが表示される」方が良い

---

## 4. オブザーバビリティ

### Atlas メトリクスシステム
- 毎秒数十億のデータポイントを処理するインメモリ時系列DB
- Spectator: メトリクス収集クライアントライブラリ
- ディメンションベースのメトリクス（タグでフィルタリング・集約）

### Edgar（分散トレーシング）
- リクエスト単位の完全なライフサイクル追跡
- サービスグラフの自動生成
- 適応的サンプリング（エラー・高レイテンシを優先）

### Lumen（自動インシデント検出）
- Atlas メトリクスをリアルタイム分析
- 統計手法（移動平均、標準偏差、MAD）で異常自動検出

---

## 5. デプロイメントとリリース

### カナリアデプロイ（Kayenta）

```
1. ベースライン群 + カナリア群を新規作成（同時立ち上げ）
2. 30分〜数時間メトリクス収集
3. Mann-Whitney U 検定で統計的比較
4. スコア閾値判定 → 合格: 全体デプロイ / 不合格: ロールバック
```

**スコアリング:**
- Critical メトリクスが1つでも Fail → カナリア全体 Fail
- ベースライン群は既存本番ではなく**新規作成**（キャッシュ差異を排除）

### Red/Black デプロイメント
```
1. [Red: v1 アクティブ] ← 全トラフィック
2. [Red: v1] + [Black: v2 準備中]
3. LB切替 → [Black: v2 アクティブ] ← 全トラフィック
4. Red v1 を一定期間保持後削除
```

### Spinnaker
- マルチクラウド対応 CD プラットフォーム
- Kayenta カナリア分析をパイプラインステージとして統合
- クラスター管理、スケーリングポリシー

**典型的なパイプライン:**
```
[Build] → [Bake AMI] → [カナリアデプロイ] → [Kayenta分析 30分]
→ 合格: [Red/Black本番デプロイ] / 不合格: [ロールバック+アラート]
→ [デプロイ後ヘルスチェック] → [旧ASG縮退]
```

### イミュータブルインフラストラクチャ
- サーバーは一度デプロイされたら変更しない
- 変更が必要な場合は新しいイメージを作成・デプロイ
- 構成ドリフトが発生しない

---

## 6. 文化的プラクティス

### Freedom and Responsibility
- サービスチームは技術スタック、アーキテクチャ、デプロイ頻度を自律的に決定
- 信頼性、パフォーマンス、コストに完全に責任を持つ

### Highly Aligned, Loosely Coupled
- 組織の戦略・目標を明確に共有（高度な整合）
- チーム間の調整コストを最小化（疎結合）
- マイクロサービスはこの組織原則の技術的な反映

### Paved Road（舗装された道）
- 中央チームが推奨ツール・プラクティスを提供
- 強制はせず、「舗装された道を走れば快適」というアプローチ
- 舗装道路: Spinnaker、Atlas、Zuul 等

---

## 7. チェックリスト

### カオスエンジニアリング実施
- [ ] 定常状態メトリクスが定義されている
- [ ] 自動監視とアラートが設定されている
- [ ] 障害注入の対象と範囲が明確
- [ ] 自動停止機構（kill switch）が用意されている
- [ ] 爆発半径が制限されている
- [ ] 営業時間内実行のスケジュール設定
- [ ] ロールバック手順が明確

### レジリエンス設計
- [ ] 全外部依存にサーキットブレーカー設定
- [ ] 全サービス呼び出しにタイムアウト設定
- [ ] 適切なフォールバック戦略が定義
- [ ] バルクヘッドでリソース分離
- [ ] リトライにエクスポネンシャルバックオフ + ジッター
- [ ] Critical Path と Non-Critical Path の区別
