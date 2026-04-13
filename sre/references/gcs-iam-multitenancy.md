# GCS IAM とマルチテナント SaaS 設計

## allUsers 公開バケットにおけるテナント分離

### 問題: `roles/storage.objectViewer` は list 権限を含む

```
$ gcloud iam roles describe roles/storage.objectViewer --format=json
{
  "includedPermissions": [
    "resourcemanager.projects.get",
    "resourcemanager.projects.list",
    "storage.folders.get",
    "storage.folders.list",
    "storage.managedFolders.get",
    "storage.managedFolders.list",
    "storage.objects.get",       ← CDN fill に必要
    "storage.objects.list"       ← 不要、列挙攻撃のリスク
  ]
}
```

allUsers に objectViewer を付与すると、**認証なしで全オブジェクト列挙が可能**:

```bash
# 匿名でのオブジェクト列挙（HTTP 200）
$ curl "https://storage.googleapis.com/storage/v1/b/BUCKET_NAME/o?maxResults=1000"
{
  "items": [
    { "name": "{OrganizationID}/{ContentID}", ... },
    ...
  ]
}
```

### マルチテナントでの影響

| リスク | list 可能時 | list 不可時 |
|--------|-----------|-----------|
| 全テナント一覧の取得 | 可能（prefix から OrganizationID 一覧） | 不可能 |
| 特定テナントの画像一覧 | 可能 | 不可能 |
| 下書き画像の発見 | 可能（list で全件取得） | 不可能（UUID 推測不可） |
| 個別画像へのアクセス | 可能（URL 既知なら） | 可能（URL 既知なら） |
| 顧客リストの漏洩 | 高リスク | 低リスク |

### 解決策: カスタムロールで `storage.objects.get` のみに制限

GCP は `allUsers` に対するカスタムロール付与を**公式にサポート**している。

```hcl
# カスタムロールの定義
resource "google_project_iam_custom_role" "cdn_object_reader" {
  role_id     = "cdnObjectReader"
  title       = "CDN Object Reader (get only, no list)"
  permissions = ["storage.objects.get"]
}

# バケット IAM でカスタムロールを allUsers に付与
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.assets.name
  role   = google_project_iam_custom_role.cdn_object_reader.id
  member = "allUsers"
}
```

**Terraform 共有モジュールとの互換性**: `members` 変数が `role = string` 型であれば、カスタムロール ID（`projects/{project_id}/roles/{role_id}` 形式）をそのまま渡せる。モジュール改修は不要。

### カスタムロール導入後のセキュリティ評価

- list 不可 → バケット内容の網羅的な取得は不可能
- ContentID が UUID（2^122 空間）→ ブルートフォースで個別 URL を推測するのは現実的に不可能
- OrganizationID は公開ページの HTML に含まれるため個別テナントレベルでは露出するが、全テナント一覧の一括取得は防止される
- 下書き画像も list できなければ URL を知りようがない

### オブジェクトキー設計のベストプラクティス

| パターン | 例 | 推測可能性 | list 不可時の安全性 |
|---------|-----|-----------|-------------------|
| UUID only | `a1b2c3d4-e5f6.../content.jpg` | 極めて低い | 高い |
| OrgID/UUID | `org-123/a1b2c3d4.jpg` | OrgID は推測可能、UUID は不可 | 高い（list 不可なら） |
| OrgID/slug | `org-123/hero-image.jpg` | 高い | 中程度 |
| sequential | `org-123/1.jpg, 2.jpg, ...` | 極めて高い | 低い |

現在の owned-hp は `{OrganizationID}/{ContentID(UUID)}` パターン → カスタムロールで list を排除すれば十分な安全性。

## 組織ポリシーとの整合性

### `constraints/storage.publicAccessPrevention`
- 組織レベルで `enforced` → プロジェクトで `inherited` にしても allUsers 付与不可
- 組織レベルで未設定 → プロジェクトで自由に設定可能
- 検証方法: dev で allUsers 付与が成功していれば組織レベルでは enforced でないことが実証

### `constraints/iam.allowedPolicyMemberDomains`
- allUsers / allAuthenticatedUsers をブロックする組織ポリシー
- これも dev で allUsers が付与できていれば問題なし

### 確認コマンド
```bash
# orgpolicy API が有効な場合
gcloud org-policies describe storage.publicAccessPrevention \
  --project=PROJECT_ID --effective

# API 未有効でも、実際に allUsers を付与して成功すれば実証
gcloud storage buckets add-iam-policy-binding gs://BUCKET \
  --member=allUsers --role=roles/storage.objectViewer
```

## 監査・コンプライアンス

### アクセスログの選択肢
1. **Cloud CDN ログ（Cloud Logging）**: CDN 経由のリクエストを記録。デフォルト有効。
2. **GCS アクセスログ（`log_bucket` 設定）**: GCS API への直接アクセスも記録。追加設定が必要。
3. **Cloud Audit Logs（Data Access）**: IAM 認証を経たアクセスを記録。allUsers（匿名）のアクセスは記録されない。

allUsers 公開バケットでは匿名アクセスが主であるため、Cloud CDN ログが最も有用。GCS 直アクセスの監査が必要なら GCS アクセスログを有効化する。

### 削除要求への対応
- 画像削除時は GCS オブジェクト削除 + CDN キャッシュパージが必要
- CDN の `maxTtl`（24時間）以内はキャッシュから配信される可能性
- 外部クローラ（Google 画像検索等）にインデックスされた場合は別途対応が必要
