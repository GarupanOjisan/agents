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

イベント時刻・バッチ実行時刻など、事前にピークがわかっている時間帯は min ノード数を引き上げておく。手段は 2 つ:

### 方法 1: Terraform の Managed Autoscaler schedule プロパティ（推奨）

Google Cloud の **Managed Autoscaler** は schedule-based scaling をサポートしている。Terraform で以下のように記述:

```hcl
resource "google_spanner_instance" "main" {
  name             = "colorsing-main"
  config           = "regional-asia-northeast1"
  display_name     = "ColorSing Main"

  autoscaling_config {
    autoscaling_limits {
      min_processing_units = 3000
      max_processing_units = 30000
    }
    autoscaling_targets {
      high_priority_cpu_utilization_percent = 65
      storage_utilization_percent           = 70
    }

    # スケジュールベースのオーバーライド
    asymmetric_autoscaling_options {
      replica_selection {
        location = "asia-northeast1"
      }
      overrides {
        autoscaling_limits {
          min_processing_units = 10000  # イベント時間帯は min を高く
          max_processing_units = 50000
        }
      }
    }
  }
}
```

**ColorSing での運用**:

- 大型イベント（お正月、記念配信等）は**イベント開始 1 時間前**から min を平常の 2〜3 倍に引き上げ
- 日次バッチ（03:00〜04:00）は [バッチ処理の負荷分散](./batch-load-balancing.md) を参照して min を引き上げ
- Terraform で宣言管理し、PR レビュー経由で変更（手動 GUI 変更禁止）

### 方法 2: Cloud Scheduler + Spanner Admin API（緊急・臨時用）

事前計画外の引き上げが必要な場合は Cloud Scheduler + Cloud Functions / Cloud Run で Spanner Admin API を叩いて Autoscaling config を差し替える。

```python
# Cloud Function 例
from google.cloud import spanner_admin_instance_v1

def scale_up(request):
    client = spanner_admin_instance_v1.InstanceAdminClient()
    instance = client.get_instance(name="projects/PROJECT/instances/colorsing-main")
    instance.autoscaling_config.autoscaling_limits.min_processing_units = 10000
    client.update_instance(instance=instance, field_mask={"paths": ["autoscaling_config"]})
```

- Cloud Scheduler で時刻指定でトリガー
- **IAM**: 実行 SA に `roles/spanner.admin` を付与（権限が強いので最小化推奨）
- 実運用では Terraform に寄せる方がレビュー・監査が容易

### スケジュール変更時のチェックリスト

- [ ] min が max の 10% 以上を満たす（Spanner 制約）
- [ ] 引き上げ後の合計 PU が契約上限内
- [ ] 引き下げタイミングが段階的になっている（急激なスケールダウンで abort 率上昇を避ける）
- [ ] 変更が Terraform で管理されている（手動変更禁止）
