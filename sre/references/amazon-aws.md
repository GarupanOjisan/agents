# Amazon/AWS 運用エクセレンスと信頼性

## 1. Well-Architected Framework - Operational Excellence

### 設計原則

| 原則 | 説明 |
|------|------|
| Operations as Code | インフラ、デプロイ、運用手順をすべてコード化 |
| 小規模かつ可逆的な変更 | 小さな変更を頻繁にデプロイ、ロールバックを容易に |
| 運用手順の頻繁な改善 | GameDay で手順の有効性を検証 |
| 障害を予測する | Pre-mortem 分析で潜在的障害を事前特定 |
| すべての障害から学ぶ | 振り返りで根本原因を特定し再発防止 |

### 4つのフェーズ

**Organization（組織）**: チーム責任範囲の明確化、2-pizza team 原則

**Prepare（準備）**: テレメトリー設計、Runbook/Playbook 整備、デプロイ戦略

**Operate（運用）**: ダッシュボード可視化、SLI/SLO 監視、アラート戦略

**Evolve（進化）**: 継続的改善ループ、OpsReview、技術的負債の返済

---

## 2. Well-Architected Framework - Reliability

### Foundations（基盤）

**サービスクォータ管理:**
- AWS Service Quotas で制限値を把握
- 使用率 80% 超過でアラート
- スケーリングイベント前にクォータ引き上げリクエスト

**主要クォータ例:**
| サービス | クォータ | デフォルト |
|----------|---------|-----------|
| EC2 | vCPU数（オンデマンド） | リージョンごとに異なる |
| Lambda | 同時実行数 | 1,000/リージョン |
| API Gateway | リクエスト/秒 | 10,000/アカウント |

### Workload Architecture（分散システム設計）

**非同期処理パターン:**
```
[Producer] → [SQS Queue] → [Consumer]
                ↓ (DLQ)
         [Dead Letter Queue] → [アラート/手動処理]
```
- べき等性（Idempotency）を確保
- Dead Letter Queue で処理失敗メッセージを捕捉

**障害分離:**
- バルクヘッドパターン: リソースをグループ分割、障害伝播を防止
- スタティック安定性: 依存サービス障害でも現在の動作を維持

### Failure Management

**AWS Fault Injection Simulator (FIS):**
- EC2 停止、CPU/メモリストレス
- AZ 障害シミュレーション
- ネットワーク遅延・パケットロス注入
- RDS フェイルオーバートリガー

---

## 3. Amazon の運用文化

### COE (Correction of Errors)

Amazon のポストモーテムプロセス。非難ではなく学習が目的。

**構成:**
1. **影響の概要**: いつ・何が・どの程度影響したか
2. **タイムライン**: 発生から復旧までの時系列記録
3. **5つの「なぜ」**: 根本原因に到達するまで繰り返す
4. **教訓**: 新しい発見か既知の問題か
5. **是正措置**: 短期的対処 + 長期的対策、担当者と期限を設定

**運用ルール:**
- 5 営業日以内に COE ドキュメント作成
- Blame-free 文化の徹底
- COE レビューミーティングで組織全体に共有

### "The Wheel" オンコールシステム

- プライマリ + セカンダリの2名体制
- 5分以内にアクノレッジ
- 健全性指標: TTD, TTA, TTM, TTR, ページ数

### Two-Pizza Teams とオーナーシップ

- チームサイズ: 6〜10名
- Single-Threaded Owner (STO): 各サービスの最終責任者
- 「You Build It, You Run It」: 開発チームが運用も責任を持つ

### Mechanisms over Good Intentions

| 問題 | 良い意図（NG） | 仕組み（OK） |
|------|---------------|-------------|
| デプロイミス | 「手順書をよく読む」 | CI/CD パイプライン |
| 設定変更ミス | 「ダブルチェック」 | IaC + コードレビュー |
| 障害の見逃し | 「監視をこまめに確認」 | 自動アラート + エスカレーション |

---

## 4. AWS 信頼性パターン

### Multi-AZ / Multi-Region

**Multi-AZ 構成:**
| サービス | 構成 |
|----------|------|
| EC2 | 複数 AZ の Auto Scaling Group |
| RDS | Multi-AZ（同期レプリケーション） |
| Aurora | 3 AZ × 6 コピー |
| DynamoDB | 自動3 AZ レプリケーション |

**Multi-Region パターン:**
- Active-Passive: レプリケーション、フェイルオーバー時に切替
- Active-Active: 双方向同期、両リージョンでトラフィック処理

### Auto Scaling ベストプラクティス

| ポリシー | 適用場面 |
|----------|---------|
| ターゲット追跡 | CPU 使用率 70% 維持 |
| 予測スケーリング | パターンが予測可能な負荷 |
| スケジュールベース | 既知のイベント |

- 最小キャパシティ = 1 AZ 障害に耐えられる値
- 混合インスタンスポリシーで複数タイプ指定

### サーキットブレーカー

```
[Closed] ── 障害率が閾値超過 → [Open] ── タイムアウト経過 → [Half-Open]
  ↑ 成功                        (遮断中)                     ↓
  └──────────── 成功 ──────────────────────────────── [Half-Open]
```

### リトライ（Exponential Backoff + Jitter）

```
# Full Jitter (推奨)
sleep = random(0, min(cap, base * 2^attempt))

パラメータ例:
  base = 100ms, cap = 30,000ms, max_retries = 5
```

**注意点:**
- べき等な操作のみリトライ
- リトライバジェットを設定（直近1分間の20%まで）
- 429 / 503 の Retry-After ヘッダーを尊重

### セルベースアーキテクチャ

```
[ルーティングレイヤー]
  ├── Cell 1 [Compute + Queue + DB] ← 顧客A,D,G
  ├── Cell 2 [Compute + Queue + DB] ← 顧客B,E,H
  └── Cell 3 [Compute + Queue + DB] ← 顧客C,F,I
```

- 各セルは完全に独立したインフラスタック
- 障害影響が1セル内に限定
- 個別デプロイ・カナリアデプロイが可能

### シャッフルシャーディング

通常のシャーディングとの違い: 各顧客がランダムに選ばれた**複数のシャード**に割り当てられる。

```
8シャードから2シャード選択: C(8,2) = 28通り
→ 2顧客が同じシャードセットを共有する確率 = 1/28 ≈ 3.6%
```

---

## 5. ディザスタリカバリ戦略

### RTO / RPO

- **RTO（Recovery Time Objective）**: 障害発生からサービス復旧までの許容最大時間
- **RPO（Recovery Point Objective）**: 許容できるデータ損失の最大量

### 戦略比較

| 戦略 | RTO | RPO | コスト |
|------|-----|-----|--------|
| Backup & Restore | 24h+ | 24h+ | 最低 |
| Pilot Light | 時間 | 分 | 低〜中 |
| Warm Standby | 分 | 秒〜分 | 中〜高 |
| Active/Active | 秒 | ≈0 | 最高 |

### Pilot Light
DR リージョンにコアコンポーネント（DB レプリカ）のみ常時稼働。障害時に残りを起動。

### Warm Standby
DR リージョンに縮小版を常時稼働。障害時にスケールアップ。

### Active/Active
複数リージョンで同時にトラフィック処理。障害リージョンのトラフィックを自動振り分け。

**データ同期の課題:**
- DynamoDB Global Tables（結果整合性）
- Aurora Global Database（秒未満のレプリケーション）
- 書き込み競合は Last-writer-wins またはアプリレベルの競合解決

### DR テストのベストプラクティス
1. 四半期に1回以上のフェイルオーバーテスト
2. フェイルオーバー手順を自動化
3. テーブルトップ演習 → コンポーネント単体 → フルスケールの段階的実施
4. フェイルバック手順も必ずテスト
5. 実際の RTO/RPO を計測し目標と比較
