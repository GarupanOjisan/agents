# Redis Cloud 統合監視ダッシュボード設計書

## 概要

singcolorプロジェクトのRedis Enterprise Cloud環境（Prometheus v2メトリクス → Cloud Monitoring連携）において、乱立する6つの既存ダッシュボード（計114ウィジェット）を廃止し、1枚の統合ダッシュボード（約30ウィジェット）に集約する。

## 対象環境

| 項目 | 値 |
|------|-----|
| サービス | Redis Enterprise Cloud |
| Proxy | Redis Enterprise Proxy |
| プロジェクト | singcolor |
| DB: prod | bdb=11641044（シングルノード）|
| DB: prod-cluster | bdb=14142587（Redis Cluster）|
| 移行状態 | prod → prod-cluster 移行中 |
| ROF | 未使用 |
| RediSearch | 未使用 |
| Active-Active | 未使用 |
| LDAP/CBA認証 | 未使用 |

## 設計原則

### 監視フレームワーク

RED メソッド（Rate, Errors, Duration）+ USE メソッド（Utilization, Saturation, Errors）をベースに、Redis Enterprise の3層構造（Proxy → Shard → Node）に適用する。

### レイヤー設計

| レイヤー | 役割 | 主要メトリクス接頭辞 |
|---------|------|---------------------|
| Proxy（Endpoint） | クライアント視点の真実 | `endpoint_*` |
| Shard（Redis Server） | エンジン内部状態 | `redis_server_*`, `namedprocess_*` |
| Node | インフラ基盤 | `node_*`, クラスタメトリクス |

### 設計判断

| 論点 | 決定 | 根拠 |
|------|------|------|
| レイテンシのパーセンタイル | p99を一次SLO指標、p50は補完表示 | p50はRedisで常に良好に見え異常を隠す |
| read/writeの分離 | 分離して表示 | 劣化原因が異なる（write=bgsave影響、read=Hot Key影響） |
| メモリ指標 | used_memory/maxmemory + fragmentation_ratio | フラグメンテーションが移行期に問題化するため両方必要 |
| CPU指標 | プロセスCPU優先、ノードCPU補完 | Redisシングルスレッド。プロセスCPUが直接ボトルネック |
| prod vs prod-cluster 表示 | 左右固定並列パネル | 移行中は同時比較が必須。フィルタ切替では一方しか見えない |
| allocator_*系 | 移行期のみ fragmentation_ratio で代替監視 | 移行完了後は used_memory/maxmemory のみで十分 |

## 除外するメトリクス

| カテゴリ | 除外指標 | 理由 |
|---------|---------|------|
| ROF/Flash | `bdb_bigstore_*`, `bdb_big_*`, `redis_big_*`, `redis_rocks_*`, `node_available_flash_*`, `node_bigstore_*` | ROF未使用 |
| RediSearch | `redis_server_search_*` 全て | RediSearch未使用 |
| Active-Active | `database_syncer_*`, `redis_server_repl_touch_bytes` | Active-Active未使用 |
| LDAP/CBA | `endpoint_*_ldap_*`, `endpoint_*_cba_*` | 未使用認証方式 |
| Client Caching | `endpoint_client_tracking_*`, `endpoint_disposed_commands_after_client_caching` | 未使用 |
| データ型分布 | `redis_server_hashes_items_*`, `redis_server_lists_items_*` 等 | 日常監視に過剰。調査時にad-hoc参照 |
| 低優先度 | `redis_server_used_memory_lua`, `redis_server_pubsub_*`, `redis_server_expire_cycle_cpu_milliseconds`, `license_*` | 現環境で実用的価値が低い |

## ダッシュボード構成

### Section 1: ヘルスサマリー

**目的**: 10秒チェック — 「今、死んでいないか？」

| # | ウィジェット名 | 可視化 | メトリクス | 閾値 |
|---|--------------|--------|-----------|------|
| 1 | prod DB 状態 | Scorecard | `db_status{bdb="11641044"}` | 0=正常、それ以外=異常 |
| 2 | prod-cluster DB 状態 | Scorecard | `db_status{bdb="14142587"}` | 同上 |
| 3 | クラスタクォーラム | Scorecard | `has_quorum` | 1=正常、0=緊急 |
| 4 | ライブノード比率 | Scorecard | `total_live_nodes_count / total_node_count` | 1.0=正常 |
| 5 | Dispatch Failures (5m) | Scorecard | `increase(endpoint_dispatch_failures[5m])` | 0=正常 |
| 6 | Ping Failures | Scorecard | `max(shard_ping_failures) + max(dmc_ping_failures)` | 0=正常 |

### Section 2: レイテンシ（prod | prod-cluster 並列）

**目的**: パフォーマンスの真実 — SLO直結指標

| # | ウィジェット名 | 可視化 | メトリクス |
|---|--------------|--------|-----------|
| 7 | Read Latency p50/p99（prod） | 時系列 | `histogram_quantile(0.5/0.99, sum by (le) (rate(endpoint_read_requests_latency_histogram_bucket{bdb="11641044"}[5m])))` |
| 8 | Read Latency p50/p99（prod-cluster） | 時系列 | 同上 `bdb="14142587"` |
| 9 | Write Latency p50/p99（prod） | 時系列 | `histogram_quantile(0.5/0.99, sum by (le) (rate(endpoint_write_requests_latency_histogram_bucket{bdb="11641044"}[5m])))` |
| 10 | Write Latency p50/p99（prod-cluster） | 時系列 | 同上 `bdb="14142587"` |

### Section 3: スループット & 接続

**目的**: トラフィック量と接続状態の把握

| # | ウィジェット名 | 可視化 | メトリクス |
|---|--------------|--------|-----------|
| 11 | Ops/sec（prod） | 時系列 | `rate(endpoint_read_requests{bdb="11641044"}[5m])`, `rate(endpoint_write_requests{...}[5m])`, `rate(endpoint_other_requests{...}[5m])` |
| 12 | Ops/sec（prod-cluster） | 時系列 | 同上 `bdb="14142587"` |
| 13 | 接続数 | 時系列 | `endpoint_connections_rate` per bdb |
| 14 | 接続エラー | 時系列 | `rate(endpoint_client_establishment_failures[5m])`, `rate(endpoint_maximal_connections_exceeded[5m])` |

### Section 4: メモリ & キースペース

**目的**: キャパシティ管理とeviction即時検知

| # | ウィジェット名 | 可視化 | メトリクス | 閾値 |
|---|--------------|--------|-----------|------|
| 15 | メモリ使用率（prod） | Gauge/時系列 | `sum(redis_server_used_memory{bdb="11641044"}) / db_memory_limit_bytes{bdb="11641044"} * 100` | 80% Warning, 90% Critical |
| 16 | メモリ使用率（prod-cluster） | Gauge/時系列 | 同上 `bdb="14142587"` | 同上 |
| 17 | Evicted Keys | 時系列 | `increase(redis_server_evicted_keys[5m])` per bdb | >0 で即アラート |
| 18 | キー数推移 | 時系列 | `sum(redis_server_db_keys) by (bdb)` | — |
| 19 | キャッシュヒット率 | 時系列 | `sum(redis_server_keyspace_read_hits) / (sum(redis_server_keyspace_read_hits) + sum(redis_server_keyspace_read_misses))` per bdb | — |
| 20 | フラグメンテーション比率 | 時系列 | `redis_server_mem_fragmentation_ratio` per bdb | >1.5 Warning, >2.0 Critical |

### Section 5: シャードヘルス（prod-cluster専用）

**目的**: シャード偏り検知とクラスタ内部状態

| # | ウィジェット名 | 可視化 | メトリクス | 閾値 |
|---|--------------|--------|-----------|------|
| 21 | シャード別メモリ | 時系列（マルチライン） | `redis_server_used_memory{bdb="14142587"}` by shard | — |
| 22 | シャード別CPU | 時系列（マルチライン） | `rate(namedprocess_namegroup_cpu_seconds_total{bdb="14142587",mode="user"}[5m])` by shard | — |
| 23 | メモリ偏り係数 | Scorecard | `max(redis_server_used_memory{bdb="14142587"}) / avg(redis_server_used_memory{bdb="14142587"})` | >1.3 Warning, >1.5 Critical |
| 24 | CPU偏り係数 | Scorecard | `max(cpu_rate) / avg(cpu_rate)` | >1.5 Warning, >2.0 Critical |
| 25 | Forwarding State | 時系列 | `count(redis_server_forwarding_state{bdb="14142587"} > 0)` | 計画外の>0は異常 |
| 26 | レプリケーション状態 | Scorecard | `min(redis_server_master_link_status{bdb="14142587"})` | 1=正常、0=異常 |

### Section 6: ノード & ネットワーク

**目的**: インフラ基盤のリソース監視

| # | ウィジェット名 | 可視化 | メトリクス | 閾値 |
|---|--------------|--------|-----------|------|
| 27 | ノード空きメモリ | 時系列 | `node_available_memory_bytes` per node | 10%未満で Warning |
| 28 | ネットワーク送受信 | 時系列 | `rate(node_network_receive_bytes_total[5m])`, `rate(node_network_transmit_bytes_total[5m])` per node | — |
| 29 | Egress Pending | 時系列 | `endpoint_egress_pending` | 増加トレンドで Warning |
| 30 | 証明書残日数 | Scorecard | `min(node_cert_expires_in_seconds) / 86400` | <30日で Warning |

### Section 7: 移行監視（移行完了後に削除）

**目的**: prod→prod-cluster移行の進捗と切替判断

| # | ウィジェット名 | 可視化 | メトリクス |
|---|--------------|--------|-----------|
| 31 | トラフィック比率 | 積み上げ面グラフ(100%正規化) | `rate(endpoint_read_requests + endpoint_write_requests[5m])` per bdb |
| 32 | prod リクエスト絶対値 | 時系列 | `rate(endpoint_read_requests{bdb="11641044"}[5m]) + rate(endpoint_write_requests{bdb="11641044"}[5m])` |
| 33 | prod-cluster リクエスト絶対値 | 時系列 | 同上 `bdb="14142587"` |
| 34 | 移行完了チェックリスト | テキスト | 下記参照 |

#### 移行完了チェックリスト

```
移行完了条件（全項目を確認してから prod を廃止）:
[ ] prod-cluster のリクエスト比率 > 99% を24時間維持
[ ] prod-cluster の p99 レイテンシ ≤ prod の 1.2 倍以内
[ ] prod-cluster の evicted_keys = 0
[ ] prod のリクエスト数が実質 0
[ ] prod-cluster のシャード偏り係数 < 1.3
[ ] DR手順のテスト完了（フェイルオーバーテスト）
```

## 日常監視フロー

### 10秒チェック（Section 1）
Section 1の6つのScorecardが全て緑 → 正常。1つでも赤 → 30秒チェックへ。

### 30秒チェック（Section 2-4）
レイテンシ・スループット・メモリ使用率の時系列で異常パターンを確認。

### 2分チェック（Section 5-6）
シャード偏り、ノードリソース、ネットワーク状態の詳細確認。

## 障害時ドリルダウンフロー

### Step 1（60秒）: 影響範囲の特定
Section 2 でレイテンシ悪化がread/writeどちらかを確認。

### Step 2（2-3分）: 原因カテゴリの絞り込み
- メモリ起因 → Section 4（メモリ使用率、eviction、フラグメンテーション）
- CPU起因 → Section 5（シャード別CPU）
- ネットワーク起因 → Section 6（egress_pending、ネットワーク送受信）

### Step 3: 根因特定
- Hot Key → Section 5のCPU偏り係数 + シャード別CPU
- メモリ飽和 → Section 4のevicted_keys + フラグメンテーション
- Proxy問題 → Section 1のdispatch_failures + Section 6のegress_pending

## 既存ダッシュボードの廃止

| 廃止対象 | 理由 |
|---------|------|
| Redis Cloud Node Dashboard (v2) | Section 5, 6 に統合 |
| Redis Cloud - Database Overview | Section 2, 3 に統合 |
| Redis Cloud: Shard Dashboard | 50ウィジェット中60%がROF関連で不要。必要分はSection 5に統合 |
| Redis Cloud - Cluster Status Dashboard | Section 1 に統合 |
| Redis Cloud - Database Status | Section 2, 3 に統合 |
| Redis Cloud - Database Dashboard (v2) | Section 2, 3, 4 に統合 |
