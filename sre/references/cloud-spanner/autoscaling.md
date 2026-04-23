# Spanner のオートスケーリング

## 概要

- スケールの最小値 / 最大値を指定する（min / max ノード数）
- 日時による指定もできる。イベント時は下限を高めに設定している
- スケールアウト / イン の条件を指定する
  - CPU 使用率、高優先度 CPU、ストレージ利用など

推奨設定値（汎用の目安）:

- リージョナル: `highPriorityCpu` = 65%、`totalCpu` = 70%
- マルチリージョン: `highPriorityCpu` = 45%、`totalCpu` = 50%

制約: `minNodes` は `maxNodes` の **10% 以上**（例: max=30 なら min=3 以上）。

## 手動で即スケールアウトさせる

緊急時の手順:

1. [GCP Console](https://console.cloud.google.com/spanner/instances) からインスタンスの概要ページを開く
2. 「インスタンスを編集」→「コンピューティング容量を構成する」→「スケーリング モードを選択する」→「**手動で割り当てる**」を選択して数量を上げて「保存」

## スケールダウンの注意

スケールアップは迅速、スケールダウンは段階的（デフォルトステップ 2,000 PU）。Split 再配置の時間を確保するため。

急激にノード数を下げると Split のリバランス中に abort 率が上がる。全体のノード数に対する一定割合ずつ減らす。割合はサービスごとに適切に見積もる。

## 特定の時間におけるオートスケーリングの設定を変更する

> **⚠️ 重要**: Managed Autoscaler **自体にはスケジュール（時間帯）ベースの自動スケーリング機能は存在しない**（2026 年時点の公式仕様）。`asymmetric_autoscaling_options` は**地理的に非対称なレプリカ別のスケール設定**（マルチリージョン構成で特定リージョンだけ上限を変える用途）であり、時間帯スケジューリングとは無関係。
> 時間帯で min/max を変えたい場合は、**Cloud Scheduler + Spanner Admin API で `autoscaling_config` を書き換える**方法を採る。

### 方法: Cloud Scheduler + Spanner Admin API（公式にサポートされた唯一の方法）

イベント時刻・バッチ実行時刻など、事前にピークがわかっている時間帯は Cloud Scheduler で min ノード数を引き上げる。

**構成**:

```
Cloud Scheduler (cron)  ──trigger──▶  Cloud Functions / Cloud Run
                                              │
                                              ▼
                                      Spanner Admin API
                                     (UpdateInstance で
                                      autoscaling_config を差し替え)
```

**Cloud Functions 実装例**（Python）:

```python
from google.cloud import spanner_admin_instance_v1
from google.protobuf import field_mask_pb2

def scale_spanner(request):
    """Cloud Scheduler から呼ばれて Autoscaler の min/max を差し替える"""
    payload = request.get_json()
    instance_name = "projects/PROJECT/instances/colorsing-main"

    client = spanner_admin_instance_v1.InstanceAdminClient()
    instance = client.get_instance(name=instance_name)

    # min/max を差し替え
    instance.autoscaling_config.autoscaling_limits.min_processing_units = payload["min_pu"]
    instance.autoscaling_config.autoscaling_limits.max_processing_units = payload["max_pu"]

    mask = field_mask_pb2.FieldMask(paths=["autoscaling_config"])
    client.update_instance(instance=instance, field_mask=mask)
```

**Cloud Scheduler ジョブ例**（大型イベント開始 1 時間前に min を引き上げ）:

```yaml
# Terraform
resource "google_cloud_scheduler_job" "scale_up_event" {
  name     = "spanner-scale-up-new-year-event"
  schedule = "0 22 31 12 *"   # 12/31 22:00 JST (1 時間前)
  time_zone = "Asia/Tokyo"

  http_target {
    uri         = google_cloudfunctions2_function.scale.service_config[0].uri
    http_method = "POST"
    body        = base64encode(jsonencode({ min_pu = 10000, max_pu = 50000 }))
    oidc_token { service_account_email = google_service_account.scheduler.email }
  }
}

resource "google_cloud_scheduler_job" "scale_down_event" {
  name     = "spanner-scale-down-new-year-event"
  schedule = "0 3 1 1 *"   # 1/1 03:00 JST（イベント終了後）
  time_zone = "Asia/Tokyo"
  # 同様に min=3000, max=30000 へ戻す
}
```

**ColorSing での運用**:

- 大型イベント（お正月、記念配信等）は**イベント開始 1 時間前**から min を平常の 2〜3 倍に引き上げ
- 日次バッチ（03:00〜04:00）は [バッチ処理の負荷分散](./batch-load-balancing.md) を参照して min を引き上げ
- Terraform で Cloud Scheduler と Cloud Functions を宣言管理し、PR レビュー経由で変更（手動 GUI 変更禁止）
- **IAM**: Cloud Functions の実行 SA に `roles/spanner.admin` を付与（権限が強いので最小化推奨、可能なら `spannerInstanceAdmin` カスタムロール）

### 参考: asymmetric_autoscaling_options（別用途）

`asymmetric_autoscaling_options` は**マルチリージョン構成で特定の read-only レプリカだけ min/max を別にする**機能。時間帯によるスケジュールではないので、本節の用途（時間帯ピーク対応）には使わない。

```hcl
# 例: マルチリージョンで asia-northeast1 の read-only レプリカだけ上限を上げる
autoscaling_config {
  autoscaling_limits {
    min_processing_units = 3000
    max_processing_units = 30000
  }
  asymmetric_autoscaling_options {
    replica_selection { location = "asia-northeast1" }
    overrides {
      autoscaling_limits {
        max_processing_units = 50000  # このロケーションだけ上限大
      }
    }
  }
}
```

### スケジュール変更時のチェックリスト

- [ ] min が max の 10% 以上を満たす（Spanner Managed Autoscaler 制約）
- [ ] 引き上げ後の合計 PU が契約上限（クォータ）内
- [ ] スケールダウンのスケジュールが段階的になっている（急激なスケールダウンで abort 率上昇を避ける）
- [ ] Cloud Scheduler と Cloud Functions が Terraform で管理されている（手動変更禁止）
- [ ] スケール変更履歴が Cloud Audit Logs に残る構成になっている
