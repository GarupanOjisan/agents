# Cloud CDN + GCS Backend Bucket: 実地検証に基づく知見

## 最重要事実: GCS backend bucket では allUsers が必須

Cloud CDN が GCS backend bucket からオリジンフェッチする際、**匿名リクエスト**として GCS にアクセスする。
したがって、GCS バケットが公開（`allUsers` に読み取り権限）でなければ CDN fill は 403 で失敗する。

### 公式ドキュメント根拠
- [Set up a backend bucket | Cloud CDN](https://docs.cloud.google.com/cdn/docs/setting-up-cdn-with-bucket)
- 公式手順では「Make your Cloud Storage bucket publicly readable」と明記
- `allUsers` に `roles/storage.objectViewer` を付与する手順が記載されている

### cloud-cdn-fill SA の正体（よくある誤解）

`service-{PROJECT_NUMBER}@cloud-cdn-fill.iam.gserviceaccount.com` は **GCS backend bucket の fill には使われない**。

| 用途 | 使われるか |
|------|-----------|
| GCS backend bucket からの CDN fill | **使われない**（匿名リクエスト） |
| サードパーティストレージ（S3等）からの private origin auth | 使われる |

**誤解の原因**: Terraform コードや過去のブログ記事で fill SA に objectViewer を付与するパターンが広まっているが、GCS backend bucket では効果がない。CDN は fill SA としてではなく匿名でリクエストする。

### 実地検証結果（2026-04-13、SSK-TBD/ops#2182）

```
# テスト環境: cc-owned-hp-assets-prod バケット

# ケース1: UBLA=true + fill SA のみ（allUsers なし）→ 403
$ curl -I https://assets.owned-hp-platform.canary-app.com/dog.jpg
HTTP/2 403
server: UploadServer  ← GCS オリジンからの直接エラー

# ケース2: UBLA=true + allUsers objectViewer → 200
$ curl -I https://assets.owned-hp-platform.canary-dev.app/seed-tenant-1/image.png
HTTP/2 200
server: UploadServer
age: 813  ← CDN キャッシュヒット
```

## UBLA (Uniform Bucket-Level Access) と PAP (Public Access Prevention) の関係

### UBLA
- `uniform_bucket_level_access = true` にすると、オブジェクトレベル ACL が無効化され、バケット IAM のみで制御
- allUsers 公開するなら UBLA 有効が推奨（Fine-grained だとオブジェクト個別 ACL が IAM を上書きして意図しないアクセス拒否が起きうる）
- **一度有効化すると 90 日後に不可逆**

### PAP
- `public_access_prevention = "enforced"` だと `allUsers`/`allAuthenticatedUsers` への IAM binding 追加が API レベルで拒否される
- **GCP Console で UBLA を有効化する際に PAP も同時に enforced になることがある**（Console の UI で両方チェックが入る）
- allUsers を付与するには PAP を `inherited` にする必要がある
- Terraform で管理する場合は `google_storage_bucket` の `public_access_prevention` 属性を明示的に設定

### UBLA 有効化前の Fine-grained ACL モードでの罠

Fine-grained ACL モード（UBLA=false）では:
- バケット IAM で fill SA に objectViewer を付与しても、**個別オブジェクトの ACL が優先される**
- アプリや手動でアップロードしたオブジェクトの default ACL は `project-owners: OWNER, project-editors: OWNER, project-viewers: READER` + アップローダー: OWNER
- fill SA はこれらのいずれにも該当しないため、個別オブジェクトを読めない
- **これが「fill SA で 403 になる」現象の真因だが、解決策は allUsers であって UBLA だけでは不十分**

```
# Fine-grained ACL モードでのオブジェクト ACL 例
$ gcloud storage objects describe gs://cc-owned-hp-assets-prod/dog.jpg --format='json(acl)'
{
  "acl": [
    { "entity": "project-owners-177040204626", "role": "OWNER" },
    { "entity": "project-editors-177040204626", "role": "OWNER" },
    { "entity": "project-viewers-177040204626", "role": "READER" },
    { "entity": "user-nakamura_m@canary-inc.jp", "role": "OWNER" }
  ]
}
# → fill SA が含まれていないため読めない
```

## Signed URL と allUsers の関係

### allUsers 公開時の Signed URL
- `allUsers` で GCS が公開されている場合、signed URL は **GCS レベルでは無意味**
- `storage.googleapis.com/bucket/object` で認証なしに直接アクセス可能
- CDN レベルで signed URL を強制する場合（`signedUrlCacheMaxAgeSec > 0`）、CDN エッジでは署名検証されるが、GCS 直アクセスは防げない

### 社内パターン整理

| パターン | 例 | allUsers | signed URL | 用途 |
|---------|-----|----------|-----------|------|
| 公開配信 | portal `estate_image` | あり | なし | 物件画像の公開配信 |
| 認証付き配信 | portal `realtor` | なし（fill SA） | あり | 限定コンテンツ |
| **矛盾パターン** | owned-hp PR#2182（元） | あり | あり | **不整合** |

### 推奨
- allUsers 公開なら `enable_signed_url = false`（portal `estate_image` パターンに統一）
- 認証が必要なら allUsers なし + signed URL だが、**GCS backend bucket では allUsers 必須なので、private 配信には backend service + Cloud Run/GKE 等の別アーキテクチャが必要**

## CDN 設定の注意点

### `signedUrlCacheMaxAgeSec`
- `0` = CDN は signed URL 検証を行わない（事実上 signed URL 無効）
- `> 0` = CDN が署名を検証し、検証済みレスポンスをその秒数キャッシュ
- shared/gcp/gcs モジュールではこの値を制御する変数がなく、GCP デフォルト（0）が適用される

### `negativeCaching`
- `false` = GCS からの 4xx/5xx をキャッシュしない（推奨）
- 画像アップロード直後の 404 がキャッシュされる事故を防ぐ

### キャッシュ invalidation
- 画像を削除/更新した場合、CDN キャッシュに `maxTtl`（最大 86400 秒 = 24 時間）残る
- `gcloud compute url-maps invalidate-cdn-cache` で明示的にパージ必要
- アプリ側でキャッシュバスティング（ファイル名にハッシュ含める）を検討

## トラブルシューティングチェックリスト

CDN 経由で GCS オブジェクトが 403 になった場合:

1. `curl -I` でレスポンスヘッダ確認 → `server: UploadServer` なら GCS 起因
2. `gcloud storage buckets describe` で UBLA/PAP 状態確認
3. `gcloud storage buckets get-iam-policy` で allUsers binding 確認
4. `gcloud storage objects describe` でオブジェクト ACL 確認（UBLA=false の場合）
5. `gcloud compute backend-buckets describe` で CDN/signed URL 設定確認
6. CDN キャッシュをパージして再試行（ネガティブキャッシュの可能性）
7. **「UBLA だけで解決するのでは」と安易に判断しない** — GCS backend bucket では allUsers 必須
