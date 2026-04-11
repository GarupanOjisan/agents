# GCP 信頼性・運用ベストプラクティス

## 1. GKE (Google Kubernetes Engine)

### クラスタ設計

| 特性 | リージョナル（推奨） | ゾーナル |
|------|---------------------|---------|
| コントロールプレーン | 3ゾーン分散 | 1ゾーンのみ |
| 可用性 | 高（ゾーン障害耐性） | 低 |
| メンテナンス | ローリングアップデート | ダウンタイムあり |

```bash
# リージョナルクラスタの作成
gcloud container clusters create production-cluster \
  --region=asia-northeast1 \
  --num-nodes=2 \
  --release-channel=regular \
  --enable-autorepair --enable-autoupgrade \
  --enable-ip-alias --enable-network-policy \
  --enable-vertical-pod-autoscaling
```

### Autopilot vs Standard

| 特性 | Autopilot | Standard |
|------|-----------|----------|
| ノード管理 | Google管理 | ユーザー管理 |
| コスト | Pod requestsベース | ノードベース |
| カスタマイズ | 制限あり | フルカスタマイズ |
| 推奨 | 新規・運用負荷軽減 | 高度なカスタマイズ |

### ノードプール戦略
- システム用: 安定性重視、Taint で分離
- アプリ用: オートスケーリング、maxSurge=1/maxUnavailable=0
- Spot VM 用: 非クリティカルワークロード、preStop でチェックポイント

### メンテナンスウィンドウ
```bash
gcloud container clusters update production-cluster \
  --maintenance-window-start=2024-01-01T17:00:00Z \  # JST 2:00
  --maintenance-window-end=2024-01-01T21:00:00Z \     # JST 6:00
  --maintenance-window-recurrence="FREQ=WEEKLY;BYDAY=TU,WE,TH"
```

### Release Channel
- `rapid`: 開発環境
- `regular`: 本番環境（推奨）
- `stable`: 安定性最優先
- `extended`: 長期サポート

---

## 2. Cloud Run

```bash
gcloud run deploy my-service \
  --min-instances=2 --max-instances=100 \
  --concurrency=80 --timeout=60s \
  --cpu=2 --memory=1Gi \
  --cpu-boost --startup-cpu-boost
```

- `min-instances` でコールドスタート回避
- リビジョンベースのトラフィック分割でカナリーデプロイ
- マルチリージョン + グローバル LB で高可用性

---

## 3. Cloud Spanner

### ホットスポット回避

```sql
-- BAD: 連番主キー
CREATE TABLE Bad (Id INT64 NOT NULL) PRIMARY KEY (Id);

-- GOOD: UUID
CREATE TABLE Good (Id STRING(36) NOT NULL) PRIMARY KEY (Id);

-- GOOD: タイムスタンプにシャードプレフィックス
CREATE TABLE TimeSeries (
  ShardId INT64 NOT NULL,
  Timestamp TIMESTAMP NOT NULL,
  UserId STRING(36) NOT NULL,
) PRIMARY KEY (ShardId, Timestamp DESC);
```

- インターリーブテーブルでデータコロケーション
- ステイルリード（staleness=15s）で読み取り高速化
- NULL フィルタリングインデックスの活用

### サイジング
- CPU 使用率 65% 以下に保つ（ピーク時でも80%以下）
- 1 ノード = 1000 PU ≈ 10,000 QPS (read)
- Autoscaler で min/max PU とCPUターゲットを設定

### 監視メトリクス

| メトリクス | 閾値 | アラート条件 |
|-----------|------|-------------|
| CPU utilization | < 65% | > 75% Warning, > 85% Critical |
| Request latencies P99 | < 100ms (read) | > 200ms |
| Storage utilization | < 75% | > 85% |
| Lock wait time | 低い値 | 急増 |

### バックアップ
```bash
# 自動バックアップスケジュール
gcloud spanner backup-schedules create daily-backup \
  --instance=production --database=my-db \
  --cron="0 2 * * *" --retention-duration=2592000s

# PITR（最大7日前まで）
gcloud spanner databases restore \
  --source-version-time=2026-04-11T10:00:00Z
```

---

## 4. Cloud SQL

```bash
# 高可用性インスタンス
gcloud sql instances create production-sql \
  --database-version=POSTGRES_16 \
  --availability-type=REGIONAL \
  --storage-type=SSD --storage-auto-increase \
  --enable-point-in-time-recovery \
  --backup-start-time=19:00 \
  --retained-backups-count=30
```

- `REGIONAL` 可用性タイプで自動フェイルオーバー
- Cloud SQL Auth Proxy で接続管理
- Query Insights でスロークエリ特定

---

## 5. Cloud Monitoring

### SLO モニタリング

```bash
# 可用性 SLO 作成（99.9%）
gcloud monitoring slos create \
  --service=my-api-service \
  --goal=0.999 --rolling-period-days=28

# バーンレートアラート（14.4x fast burn）
# 1時間ウィンドウで 14.4x → P1 Page
```

### アラートポリシー設計原則
- アクションにつながるアラートのみ設定
- 症状ベース（SLO ベース）を優先
- ランブックをアラートのドキュメントフィールドに記載
- 通知チャネル: Slack, PagerDuty

### ダッシュボード設計
- 最上段: ゴールデンシグナル（Rate, Error, Latency, Saturation）
- 上→下: 概要→詳細の構造
- Code として管理（JSON 定義）

---

## 6. Cloud Logging

### ログベースメトリクス
```bash
gcloud logging metrics create error-count \
  --log-filter='resource.type="k8s_container" severity>=ERROR'
```

### ログルーティング
- BigQuery シンク: 分析用
- Cloud Storage シンク: 長期保存
- ログ除外フィルタ: DEBUG、ヘルスチェックを除外してコスト最適化

### 有用なクエリ
```
# 特定リクエストIDでトレース
jsonPayload.request_id="abc-123"

# HTTP 5xx エラー調査
httpRequest.status>=500 timestamp>="2026-04-12T00:00:00Z"

# OOMKilled 検出
jsonPayload.message=~"OOMKilled"
```

---

## 7. ネットワーキング

### Cloud Load Balancing
- Outlier Detection で異常バックエンドを自動除外
- Connection draining でグレースフルシャットダウン

### Cloud Armor
```bash
# OWASP Top 10 対策
gcloud compute security-policies rules create 1000 \
  --expression="evaluatePreconfiguredExpr('xss-v33-stable')" --action=deny-403

# レートリミット
gcloud compute security-policies rules create 2000 \
  --action=throttle --rate-limit-threshold-count=100 \
  --rate-limit-threshold-interval-sec=60

# Adaptive Protection（ML異常検知）
gcloud compute security-policies update my-policy --enable-layer7-ddos-defense
```

### VPC 設計
- Shared VPC で組織内ネットワーク統合管理
- Private IP Google Access + Cloud NAT
- VPC Flow Logs でトラフィック監視

---

## 8. セキュリティ

### IAM
- Workload Identity で GKE Pod に権限付与（SA キー発行を避ける）
- グループベースの権限管理
- IAM Recommender で不要権限を定期削除

### Secret Manager
- CSI ドライバーで GKE に Secret をマウント
- ローテーション自動化（Pub/Sub + Cloud Functions）

### Binary Authorization
- 署名されたイメージのみデプロイ許可
- CI/CD で自動署名、GKE で検証

---

## 9. コスト最適化

### CUD (Committed Use Discounts)
| プラン | 割引率 |
|--------|--------|
| 1年 | 20-28% |
| 3年 | 40-52% |

ベースラインリソースに CUD、ピーク分はオンデマンド/Spot。

### Spot VM
- ステートレスワークロードのみ
- 複数マシンタイプを指定
- preStop でチェックポイント保存

### リソースサイジング
- VPA で推奨値を確認（まず Off モードで）
- Recommender API で定期確認
- Budget Alert を設定

---

## 10. インシデント対応

### GCP 障害時のフロー
```
1. GCP Status Dashboard / Service Health を確認
2. 影響範囲とビジネスインパクトを評価
3. GCP 起因 → サポートケース起票 + ワークアラウンド
   自社起因 → ログ・メトリクス調査 → ロールバック判断
4. 復旧後の正常性・データ整合性確認
5. ポストモーテム（5営業日以内）
```

### サポートケース
- Project ID、リソース名を明記
- 影響開始時刻（タイムゾーン明記）
- 実施済み調査と結果
- メトリクスのスクリーンショット
- ビジネスインパクト（S1/S2 は特に重要）

### Uptime Check
```bash
gcloud monitoring uptime create my-check \
  --resource-type=uptime-url \
  --monitored-resource-hostname=api.example.com \
  --protocol=HTTPS --path=/healthz --period=60
```
