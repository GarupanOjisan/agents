# Cloud Logging → BigQuery シンクの構造的問題の解消

## ステータス

| 項目 | 内容 |
|------|------|
| 起票日 | 2026-04-12 |
| 対象プロジェクト | singcolor |
| 優先度 | 高 |
| 主目的 | BQ シンクの `table_invalid_schema` エラー頻発を構造的に解消する |
| 副次効果 | Logging コストの最適化（月額 $1,100〜$1,500 削減見込み） |

---

## 1. 課題

### 1.1 table_invalid_schema エラーの頻発

Cloud Logging から BigQuery へのシンク `app_log_subscriber_bq` で、毎日のように以下のエラーが発生している。

```
Error Code: table_invalid_schema
Error Detail: Cannot convert value to floating point (bad value): db2a24f0-ca86-450d-aad1-48d01666b9b4
```

**原因:** BQ シンクの自動スキーマ推論は、最初に到達した値で型を決定する。あるフィールドに最初に数値が入ると `FLOAT64` カラムとして定義され、後から UUID 文字列が来ると型変換に失敗してログがドロップされる。

**対処しても再発する理由:** アプリのログは jsonPayload に自由にフィールドを追加できるため、新しいフィールドや値の型変更が発生するたびに同じ問題が起きる。テーブルの作り直しや型修正は対症療法であり、構造的に解消できない。

### 1.2 BQ カラム数上限の問題

jsonPayload のフィールド数が多く、`app_log_subscriber_bq` と `app_log_info_bq` を統合すると BigQuery のカラム数上限（10,000）を超える。このため subscriber 系とそれ以外でシンクとデータセットを分割して運用している。

フィールドが増えるたびに再びカラム数上限に近づくため、この運用も長期的には持続できない。

### 1.3 コストが最適化されていない

Logging 関連の月額コストは約 **$2,627/月**（年間 $31,500）だが、実データを分析した結果、大部分が調査価値の低いログの取り込み料金であることが判明した。

---

## 2. 現状分析

### 2.1 Logging 取り込み量（実測: 直近30日）

| 指標 | 値 |
|------|-----|
| 30日合計 | 4.49 TiB (4,594 GiB) |
| 平均/日 | 153 GiB |
| 月額取り込み料金 | $2,272（全コストの **87%**） |

#### リソースタイプ別内訳（直近7日）

| リソースタイプ | 7日合計 | 割合 | 用途 |
|--------------|--------|------|------|
| `k8s_container` | 613 GiB | 54.6% | GKE アプリログ |
| `http_load_balancer` | 235 GiB | 20.9% | LB アクセスログ |
| `api` | 230 GiB | 20.5% | Cloud Endpoints ログ |
| `k8s_node` / `gce_instance` / その他 | 44 GiB | 4.0% | インフラ系 |

#### ログの実態（サンプリング調査結果）

| カテゴリ | 実態 |
|---------|------|
| k8s_container の severity | INFO **98.6%**, WARNING 1.2%, ERROR 0.2% |
| http_load_balancer の status | **200 が 99%以上**、4xx/5xx はごく少数 |
| api の logName | **100% が Cloud Endpoints ログ**（Data Access audit ではない） |
| 除外フィルタ | **ゼロ（一切の除外を設定していない）** |

### 2.2 BQ シンクの全体像

#### 活きているシンク（2個）

| シンク名 | 対象 | BQ データセット | サイズ |
|----------|------|----------------|--------|
| `app_log_subscriber_bq` | `container_name=~".+-subscriber"` | `app_log_subscriber` (11 テーブル) | 163 GiB |
| `app_log_info_bq` | subscriber 以外の全 prod コンテナ | `app_log_info` (64 テーブル) | 715 GiB |

#### 死んでいるシンク（9個、書き込み停止済み）

| シンク名 | 最終書き込み | BQ データセット | サイズ |
|----------|------------|----------------|--------|
| `app_error_log_bq` | 2023-10-29 | `app_log_errors` (3 テーブル) | 9 GiB |
| `sink-log-send-gift` | 2023-05-25 | `sink_log_send_gift` (1,000 テーブル) | 307 GiB |
| `sink-log-live-score-ranking` | 2023-06-10 | `sink_log_live_score_ranking` (1,000 テーブル) | 256 GiB |
| `sink-log-publish-live-event` | 2023-08-08 | `sink_log_publish_live_event` (979 テーブル) | 1,268 GiB |
| `sink-log-multi-account-limit` | 2024-04-10 | `sink_log_multi_account_limit` (731 テーブル) | 80 GiB |
| `sink-log-live-score-and-source` | 2024-01-29 | `sink_log_live_score_and_source` (803 テーブル) | 4 GiB |
| `sink-log-promote-league` | 2023-06-06 | `sink_log_promote_league` (1,000 テーブル) | 3 GiB |
| `sink-log-promotion-meter-border-at-closing-time` | 2023-05-25 | 同名 (1,000 テーブル) | 1 GiB |
| `sink-log-violation-handling` | 2023-05-25 | `sink_log_violation_handling` (754 テーブル) | 0 GiB |
| **合計** | | **7,270 テーブル** | **約 1,928 GiB** |

これらは 2〜3 年間書き込みがなく、BQ Long-term storage 料金（$0.016/GiB/月）のみ発生中。月額約 $31。

### 2.3 現状のコスト構造

| コスト項目 | 月額 | 全体比 |
|-----------|-----:|------:|
| Logging 取り込み (4,544 GiB × $0.50) | $2,272 | 87% |
| BQ シンク活（Streaming Insert + Storage） | $324 | 12% |
| BQ 死んだデータセット（Long-term Storage） | $31 | 1% |
| **合計** | **$2,627** | 100% |

→ **コストの 87% は取り込み料金。** シンク先をどう変えるかより、不要なログを取り込まないことが最もコスト効果が高い。

---

## 3. 提案

2 フェーズに分けて段階的に実施する。Phase 1 で主目的（BQ シンクの構造的問題解消）を達成し、Phase 2 で副次的なコスト最適化を行う。

### Phase 1: BQ シンク全廃 → Log Analytics 移行（主目的）

**期間: 1〜2 週間 / リスク: 中 / 効果: table_invalid_schema 根絶 + カラム数上限問題の解消**

BQ シンクを廃止し、カスタムログバケット + Log Analytics + BQ linked dataset に移行する。これにより `table_invalid_schema` エラーが原理的に発生しなくなり、カラム数上限の問題も解消する。

#### なぜ Log Analytics か

| 観点 | BQ シンク（現状） | Log Analytics + Linked Dataset |
|------|-----------------|-------------------------------|
| スキーマ | 自動推論で型固定。型揺れで即死 | JSON のまま保持。型揺れの影響なし |
| カラム数 | 10,000 上限に抵触 | jsonPayload は JSON 型 1 カラム。上限なし |
| ストレージ | Logging + BQ の二重保管 | Logging バケットのみ。コピーなし |
| コスト | Streaming Insert + BQ Storage | Logging 保管料のみ（30 日超は $0.01/GiB/月） |
| SQL 調査 | BQ コンソールで直接クエリ | BQ linked dataset 経由で同じ BQ コンソールからクエリ |

#### 構成

```
GKE Pod (stdout JSON)
  │
  ▼
Cloud Logging
  ├── _Default bucket (14 日保持、変更なし)
  │
  └── ops-archive bucket (180 日保持、Log Analytics 有効)
        ├── ルーティング: prod namespace の全コンテナログ
        └── BQ linked dataset → BQ コンソールから SQL 調査可能
```

#### 実施手順

```bash
# Step 1: カスタムログバケット作成
gcloud logging buckets create ops-archive \
  --project=singcolor \
  --location=global \
  --retention-days=180 \
  --enable-analytics

# Step 2: prod コンテナログをルーティング
gcloud logging sinks create ops-archive-sink \
  logging.googleapis.com/projects/singcolor/locations/global/buckets/ops-archive \
  --project=singcolor \
  --log-filter='resource.labels.cluster_name="singcolor" AND resource.labels.namespace_name="prod"'

# Step 3: BQ linked dataset 作成
gcloud logging links create ops-archive-link \
  --bucket=ops-archive \
  --location=global \
  --project=singcolor

# Step 4: 動作確認（1〜2 週間並走）
# → BQ コンソールで linked dataset にクエリを実行し、期待通りのデータが取れることを確認

# Step 5: 既存 BQ シンク 2 個を削除
gcloud logging sinks delete app_log_subscriber_bq --project=singcolor --quiet
gcloud logging sinks delete app_log_info_bq --project=singcolor --quiet
```

#### クエリの書き換え例

旧（BQ シンク）:
```sql
SELECT
  timestamp,
  jsonPayload.user_id,
  jsonPayload.latency_ms
FROM `singcolor.app_log_subscriber.stdout_*`
WHERE severity = 'ERROR'
  AND _TABLE_SUFFIX >= '20260401'
```

新（Log Analytics linked dataset）:
```sql
SELECT
  timestamp,
  JSON_VALUE(json_payload, '$.user_id') AS user_id,
  SAFE_CAST(JSON_VALUE(json_payload, '$.latency_ms') AS FLOAT64) AS latency_ms
FROM `singcolor.global.ops-archive._AllLogs`
WHERE severity = 'ERROR'
  AND timestamp >= '2026-04-01'
```

> `SAFE_CAST` を使えば、型が混在していても NULL が返るだけでエラーにならない。

#### Phase 1 の効果

| 項目 | 変化 | 月額影響 |
|------|------|--------:|
| BQ Streaming Insert 廃止 | 不要に | -$30 |
| BQ Active/Long-term Storage 廃止 | 不要に | -$294 |
| ログバケット 180 日保管追加 | 新規 | +$135 |
| **コスト純削減** | | **-$189/月** |
| **table_invalid_schema** | **根絶** | - |
| **カラム数上限問題** | **解消** | - |

---

### Phase 2: コスト最適化（副次目的）

Phase 1 で BQ シンクの問題を解消した後に、取り込みコストの最適化を行う。

**期間: Phase 1 完了後に段階的に適用 / リスク: 低 / 月額削減: 約 $950**

#### 施策 2-1: LB 2xx/3xx レスポンスログの除外（-$475/月）

LB ログの 99% 以上が HTTP 200。正常レスポンスのアクセスログは調査価値がほぼなく、トラブルシューティングに必要なのは 4xx/5xx のエラーレスポンスのみ。

```bash
gcloud logging sinks update _Default \
  --project=singcolor \
  --add-exclusion=name=exclude-lb-success,filter='resource.type="http_load_balancer" httpRequest.status<400'
```

#### 施策 2-2: Cloud Endpoints 正常ログの除外（-$448/月）

api ログは 100% が Cloud Endpoints のリクエストログ。LB ログと情報が重複しており、ERROR/WARNING は残しつつ INFO を除外する。

```bash
gcloud logging sinks update _Default \
  --project=singcolor \
  --add-exclusion=name=exclude-endpoints-info,filter='resource.type="api" severity="INFO"'
```

#### 施策 2-3: 死んだシンク 9 個と BQ データセットの整理

2〜3 年間書き込みがないシンク 9 個が存在する。シンク定義の削除だけではコスト削減にならない（既に書き込みが止まっているため）。**コスト削減にはシンク定義の削除に加えて、BQ データセット/テーブルの削除が必要。**

```bash
# シンク定義の削除（ルーティング設定のクリーンアップ）
for sink in app_error_log_bq \
  sink-log-send-gift \
  sink-log-live-score-ranking \
  sink-log-promote-league \
  sink-log-promotion-meter-border-at-closing-time \
  sink-log-pubish-live-event \
  sink-log-live-score-and-source \
  sink-log-multi-account-limit \
  sink-log-violation-handling; do
  gcloud logging sinks delete ${sink} --project=singcolor --quiet
done

# BQ データセットの削除（実際のコスト削減はこちら）
# ※ チームに確認の上、不要であることを確認してから実行
# ※ 必要なデータがあれば事前に GCS にエクスポートすること
for ds in app_log_errors \
  sink_log_send_gift \
  sink_log_live_score_ranking \
  sink_log_promote_league \
  sink_log_promotion_meter_border_at_closing_time \
  sink_log_publish_live_event \
  sink_log_live_score_and_source \
  sink_log_multi_account_limit \
  sink_log_violation_handling; do
  bq rm -r -f singcolor:${ds}
done
```

#### 施策 2-4: 更なる最適化（オプション）

| 施策 | 内容 | 追加削減/月 | リスク |
|------|------|----------:|--------|
| k8s_container INFO のサンプリング除外 | live-subscriber / live-score-subscriber の INFO を 90% 除外 | $300〜$400 | 中: 調査時に該当ログが欠ける可能性。段階的に検証が必要 |
| _Default バケットの保持期間短縮 | 14 日 → 1 日 | 微小 | 低: ops-archive に 180 日保持があるため冗長 |

#### Phase 2 の効果

| 施策 | 取り込み削減量/月 | コスト削減/月 | リスク |
|------|---------------:|------------:|--------|
| LB 2xx/3xx 除外 | 950 GiB | $475 | 4xx/5xx は残る。影響なし |
| Endpoints INFO 除外 | 895 GiB | $448 | ERROR/WARNING は残る。影響なし |
| 死んだ BQ データセット削除 | - | $31 | チームに要確認。削除は不可逆 |
| **合計** | **1,845 GiB** | **約 $954/月** | |

> **注意:** 除外フィルタは不可逆（除外されたログは Logging に取り込まれない）。適用前に Logs Explorer でサンプルを確認し、除外対象が想定通りであることを検証すること。

---

## 4. コスト比較サマリ

| | 現状 | Phase 1 後 | Phase 1+2 後 |
|---|---:|---:|---:|
| Logging 取り込み | $2,272 | $2,272 | **$1,349** |
| BQ シンク（活） | $324 | **$0** | $0 |
| ログバケット 180 日保管 | $0 | $135 | $135 |
| BQ 死んだデータセット | $31 | $31 | **$0** |
| **月額合計** | **$2,627** | **$2,438** | **$1,484** |
| **年間合計** | **$31,524** | **$29,256** | **$17,808** |
| **現状比削減** | - | **-$189/月 (-7%)** | **-$1,143/月 (-44%)** |

---

## 5. リスクと注意事項

### Log Analytics 移行に関するリスク（Phase 1）

- **クエリ性能:** BQ ネイティブテーブルより遅い（カラムナー最適化が効かない）。ただし低頻度のアドホック調査では問題にならない
- **クエリ構文の変更:** `jsonPayload.field` → `JSON_VALUE(json_payload, '$.field')` への書き換えが必要
- **並走期間:** 既存 BQ シンクと新しいログバケットを 1〜2 週間並走させてから移行する

### 除外フィルタに関するリスク（Phase 2）

- **不可逆:** 除外されたログは Cloud Logging に取り込まれない。後から遡って確認することはできない
- **緩和策:** 除外対象は「正常系」（LB 2xx、Endpoints INFO）に限定しており、エラー系は全て残る。トラブルシューティングへの影響は最小限
- **段階適用:** 一度に全除外せず、1〜2 週間間隔で効果と影響を確認しながら適用する

### 死んだデータセットの削除に関するリスク（Phase 2）

- BQ のデータセット・テーブルは一度削除すると復元できない（タイムトラベル期間を除く）
- **対応:** 削除前にチームに確認し、必要なデータがあれば GCS にエクスポートしてから削除する

---

## 6. 実施スケジュール

| 期間 | フェーズ | アクション | 効果 |
|------|---------|-----------|------|
| **1 日目** | Phase 1 | カスタムバケット・Log Analytics 構築 | 基盤準備 |
| **1〜2 週間** | Phase 1 | 並走確認、サンプルクエリ検証 | 移行リスク低減 |
| **2〜3 週目** | Phase 1 | 既存 BQ シンク 2 個削除 | table_invalid_schema 根絶、-$189/月 |
| **Phase 1 完了後** | Phase 2 | 除外フィルタ適用（段階的） | -$923/月 |
| **Phase 2 以降** | Phase 2 | 死んだシンク・BQ データセット削除、オプション施策 | -$31/月 + 追加 $300+/月 |
