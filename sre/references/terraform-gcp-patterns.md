# Terraform GCP パターン集: 実地検証に基づく知見

## 共有モジュール設計

### 変数の nullable と default の罠

```hcl
# 危険: nullable = true だが default がない
variable "retention_duration_seconds" {
  type        = number
  nullable    = true
  # default がない → 呼び出し側で必ず指定が必要
  # モジュール ref を bump した瞬間、指定していない呼び出し側が壊れる
}

# 安全: default = null を明示
variable "retention_duration_seconds" {
  type        = number
  nullable    = true
  default     = null  # 既存の呼び出し側に影響なし
}
```

### 新しい属性を共有モジュールに追加する手順

1. `variables.tf` に変数追加（**必ず default 値を設定**して既存呼び出し側を壊さない）
2. `gcs.tf`（メインリソース）に属性追加
3. コミット → 新しいコミットハッシュを取得
4. 呼び出し側で `ref=` を新ハッシュに更新
5. `terraform plan` で差分確認 → apply

### public_access_prevention の管理

GCS バケットの `public_access_prevention` は Terraform で明示管理すべき。

```hcl
# variables.tf
variable "public_access_prevention" {
  type        = string
  description = "Public access prevention: 'inherited' or 'enforced'"
  default     = "inherited"
  nullable    = false
}

# gcs.tf
resource "google_storage_bucket" "default" {
  name                        = var.name
  location                    = var.location
  storage_class               = var.storage_class
  force_destroy               = var.force_destroy
  project                     = var.project_id
  uniform_bucket_level_access = var.uniform_bucket_level_access
  public_access_prevention    = var.public_access_prevention  # 追加
  ...
}
```

**注意**: GCP Console で UBLA を有効化すると PAP も `enforced` に変更されることがある。Terraform で `inherited` を指定していないと、手動変更が state に反映されず drift する。

## State Drift の検出と収束

### よくある drift パターン

| 操作 | state | 実態 | plan 出力 |
|------|-------|------|----------|
| Console で UBLA 有効化 | false | true | `~ uniform_bucket_level_access = false -> true` |
| Console で PAP enforced | 未管理 | enforced | （属性未管理なら差分出ない＝サイレント drift） |
| gcloud で allUsers 追加 | なし | あり | `+ google_storage_bucket_iam_member.default["allUsers"]`（新規追加として認識） |
| gcloud で allUsers 追加済み + Terraform で追加 | なし | あり | no-op（terraform import 相当の収束） |

### サイレント drift の危険性

Terraform で管理していない属性（`public_access_prevention` 等）は `terraform plan` に差分が出ない。
しかし `terraform apply` 時に他の属性変更と一緒に GCS API に送信され、**意図しない属性リセット**が起きる場合がある。

**対策**: 新しい属性は積極的に Terraform 変数化して明示管理する。

### drift 収束の安全な手順

```bash
# 1. 現状確認
gcloud storage buckets describe gs://BUCKET --format=json

# 2. Terraform plan で差分確認
terraform plan -target=module.assets

# 3. 差分が「収束方向」（実態 → コード）であることを確認
# 4. apply
terraform apply -target=module.assets
```

## IAM Member の for_each キー変更

### 問題

共有 GCS モジュールの IAM binding:
```hcl
resource "google_storage_bucket_iam_member" "default" {
  for_each = { for i in var.members : i.member => i }
  role     = each.value["role"]
  member   = each.value["member"]
}
```

`member` 文字列が for_each のキーのため、member を変更すると **旧キーの destroy + 新キーの create** になる。

例: `serviceAccount:...@cloud-cdn-fill.iam.gserviceaccount.com` → `allUsers`
- 旧 SA の binding が destroy
- `allUsers` の binding が create
- **一瞬だけどちらの binding もない状態が発生しうる**

### 対策
- `google_storage_bucket_iam_member` は additive（authoritative でない）ため、他の binding には影響しない
- ダウンタイムは数秒程度
- 懸念がある場合は 2-step（先に追加 → 次に削除）で実施

## モジュール ref 管理

### ref bump の原則
- `ref=` には特定のコミットハッシュを指定（ブランチ名やタグではなく）
- 同一ファイル内の複数モジュールは同じ ref に揃えることが望ましいが、必須ではない
- ref bump 時は `terraform plan` で意図しない変更がないか必ず確認

### ref bump と無関係な変更が混入するケース
- `ref=` を最新コミットに bump すると、GCS モジュールと無関係な変更（他ディレクトリのコミット）も含まれる
- 機能的には GCS モジュールのファイル（`gcs.tf`, `variables.tf`, `outputs.tf`）に変更がなければ影響なし
- `git diff OLD_REF..NEW_REF -- terraform/shared/gcp/gcs/` で差分確認

## Apply 順序の設計

### 共有モジュール変更を含む場合

```
1. 共有モジュール変更をコミット（main にマージ）
2. 呼び出し側 PR で ref を新コミットハッシュに更新
3. dev で terraform plan → apply → 動作確認
4. 一定期間（1日〜1週間）運用観察
5. prod で terraform plan → apply
```

### UBLA + allUsers を同時適用する場合の注意

- UBLA 有効化とallUsers 付与は同一 `terraform apply` で実行可能
- ただし PAP が enforced の場合、先に PAP を inherited に変更する必要がある
- `terraform plan` で PAP 変更 → allUsers 追加が正しい順序で処理されることを確認

## カスタムロールの Terraform 管理

```hcl
# プロジェクトレベルのカスタムロール
resource "google_project_iam_custom_role" "cdn_object_reader" {
  project     = var.project_id
  role_id     = "cdnObjectReader"
  title       = "CDN Object Reader (get only, no list)"
  description = "Cloud CDN fill 用の最小権限ロール。storage.objects.get のみ。"
  permissions = ["storage.objects.get"]
  stage       = "GA"
}

# 使用例（共有モジュールの members に渡す）
module "assets" {
  ...
  members = [
    {
      role   = google_project_iam_custom_role.cdn_object_reader.id
      member = "allUsers"
    },
    {
      role   = "roles/storage.objectAdmin"
      member = "serviceAccount:${local.app_sa}"
    },
  ]
}
```

**注意**: `google_project_iam_custom_role.cdn_object_reader.id` は `projects/{project_id}/roles/cdnObjectReader` 形式の文字列を返す。共有モジュールの `members.role` が `string` 型なら互換性あり。
