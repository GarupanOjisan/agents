# Redis Enterprise Cloud 運用・監視ベストプラクティス

## 1. アーキテクチャ概要

### 3層構造

```
Client → Redis Enterprise Proxy (DMC) → Shard (Redis Process) → Node (VM)
```

| レイヤー | 役割 | メトリクス接頭辞 |
|---------|------|-----------------|
| Proxy（Endpoint） | MOVED/ASK を隠蔽し透過ルーティング | `endpoint_*` |
| Shard（Redis Server） | データ処理エンジン（シングルスレッド） | `redis_server_*`, `namedprocess_*` |
| Node | 物理/仮想マシン基盤 | `node_*` |

### Redis Enterprise Proxy の特性
- クライアントからはシングルエンドポイント
- MOVED/ASK リダイレクトを完全隠蔽
- read/write/other にリクエストを分類してメトリクス記録
- パイプラインをシャード別サブパイプラインに分割
- 問題がどの層で発生しているかの特定が困難になるため、Proxy固有の指標を独立監視することが重要

---

## 2. 監視メトリクス体系（Prometheus v2）

### Endpoint（Proxy）メトリクス

#### スループット

| メトリクス | 型 | 説明 |
|-----------|-----|------|
| `endpoint_read_requests` | counter | 読み取りリクエスト数 |
| `endpoint_write_requests` | counter | 書き込みリクエスト数 |
| `endpoint_other_requests` | counter | その他リクエスト数 |
| `endpoint_read_responses` / `write_responses` / `other_responses` | counter | レスポンス数（リクエストとのdiffでドロップ検知） |

#### レイテンシ

| メトリクス | 型 | 説明 |
|-----------|-----|------|
| `endpoint_read_requests_latency_histogram_bucket` | histogram | 読み取りレイテンシ（μs） |
| `endpoint_write_requests_latency_histogram_bucket` | histogram | 書き込みレイテンシ（μs） |
| `endpoint_other_requests_latency_histogram_bucket` | histogram | その他レイテンシ（μs） |

p99を一次SLO指標とする。p50はRedisでは常に良好に見えて異常を隠す。read/writeは分離監視（劣化原因が異なる: write=bgsave影響、read=Hot Key影響）。

#### 接続

| メトリクス | 型 | 説明 |
|-----------|-----|------|
| `endpoint_connections_rate` | gauge | 受信接続レート |
| `endpoint_accepted_connections` | counter | 受け入れた接続総数 |
| `endpoint_client_establishment_failures` | counter | 接続確立失敗数 |
| `endpoint_maximal_connections_exceeded` | counter | 最大接続数超過 |
| `endpoint_proxy_disconnections` | counter | Proxy主導の強制切断 |
| `endpoint_dispatch_failures` | counter | シャードへのディスパッチ失敗 |

#### バックプレッシャー

| メトリクス | 型 | 説明 |
|-----------|-----|------|
| `endpoint_egress_pending` | counter | 送信待機バイト数（増加=出力ボトルネック） |
| `endpoint_egress_pending_discarded` | counter | 破棄された送信データ（>0で即アラート） |
| `endpoint_longest_pipeline_histogram` | counter | パイプライン深度分布 |
| `endpoint_rate_limit_overflows` | counter | レートリミット超過 |

#### ヘルスチェック

| メトリクス | 型 | 説明 |
|-----------|-----|------|
| `endpoint_ping_failures` | gauge | Proxy外部からのPING失敗 |
| `dmc_ping_failures` | gauge | Proxy→DMC管理チャネル失敗 |
| `shard_ping_failures` | gauge | Proxy→シャードPING失敗 |

**障害レイヤー切り分け:**
- `endpoint_ping_failures` のみ上昇 → Proxyリソース問題またはProxy-Client間ネットワーク
- `dmc_ping_failures` 上昇 → 制御プレーン異常。フェイルオーバー判定遅延の可能性
- `shard_ping_failures` 上昇 → データプレーン異常。`dispatch_failures` の前兆

### DB メトリクス

| メトリクス | 型 | 説明 |
|-----------|-----|------|
| `db_status` | gauge | 0=active, 1=active-change-pending, 2=pending, 3=import-pending, 4=delete-pending, 5=recovery |
| `db_memory_limit_bytes` | gauge | RAM制限 |
| `db_replication_factor` | gauge | レプリケーション係数 |

### Redis Server（Shard）メトリクス

#### メモリ

| メトリクス | 閾値 | 説明 |
|-----------|------|------|
| `redis_server_used_memory / redis_server_maxmemory` | 80% Warning, 90% Critical | メモリ使用率（最重要） |
| `redis_server_mem_fragmentation_ratio` | >1.5 Warning, >2.0 Critical | フラグメンテーション比率 |
| `redis_server_evicted_keys` | rate > 0 で即アラート | eviction発生（メモリ飽和到達済み） |

#### キースペース

| メトリクス | 説明 |
|-----------|------|
| `redis_server_db_keys` | キー総数 |
| `redis_server_keyspace_read_hits / read_misses` | キャッシュヒット率計算用 |
| `redis_server_expired_keys` | 期限切れキー数 |

#### レプリケーション

| メトリクス | 説明 |
|-----------|------|
| `redis_server_master_link_status` | 1=接続中, 0=切断（30秒で Warning, 120秒で Critical） |
| `redis_server_master_sync_in_progress` | 1=全量同期中 |
| `redis_server_forwarding_state` | >0=スロット移動中（リシャーディング） |
| `redis_server_connected_slaves` | 期待値=`db_replication_factor - 1` |

### Redis Process メトリクス

| メトリクス | 説明 |
|-----------|------|
| `namedprocess_namegroup_cpu_seconds_total` | プロセスCPU（mode=user/system）。ノードCPUより直接的 |
| `namedprocess_namegroup_open_filedesc` | FD使用量。枯渇でdispatch_failures |
| `namedprocess_namegroup_thread_count` | スレッド数（シャード数計算） |

### Node メトリクス

| メトリクス | 説明 |
|-----------|------|
| `node_available_memory_bytes` | ノード利用可能メモリ（10%未満で Warning） |
| `node_metrics_up` | 1=正常, 0=障害 |
| `node_cert_expires_in_seconds` | 証明書残秒数（<30日で Warning） |
| `node_ephemeral_storage_free_bytes` | エフェメラルディスク空き |

### Cluster メトリクス

| メトリクス | 説明 |
|-----------|------|
| `has_quorum` | 1=正常, 0=クォーラム喪失（即アラート） |
| `total_live_nodes_count / total_node_count` | ノード稼働率 |

---

## 3. 監視設計パターン

### ゴールデンシグナル（RED）への対応

| シグナル | 一次指標 | レイヤー |
|---------|---------|---------|
| Rate | `endpoint_read/write/other_requests` | Proxy |
| Errors | `endpoint_dispatch_failures`, `endpoint_client_establishment_failures` | Proxy |
| Duration | `endpoint_*_latency_histogram_bucket` (p99) | Proxy |

### USEメソッドへの対応

| シグナル | 指標 |
|---------|------|
| Utilization | `redis_server_used_memory / maxmemory`, `namedprocess_*_cpu` |
| Saturation | `endpoint_egress_pending`, `redis_server_blocked_clients`, `evicted_keys` |
| Errors | `dmc_ping_failures`, `shard_ping_failures`, `has_quorum` |

### シャード偏り検知

偏り係数 = max(metric) / avg(metric)

| 偏りパターン | 一次指標 | 閾値 |
|-------------|---------|------|
| Hot Key CPU偏り | `namedprocess_*_cpu` by shard | >1.5 Warning, >2.0 Critical |
| メモリ偏り | `redis_server_used_memory` by shard | >1.3 Warning, >1.5 Critical |
| トラフィック偏り | `redis_server_keyspace_*_hits` by shard | >1.4 Warning, >2.0 Critical |

### 障害ドリルダウンフロー

```
Step 1（60秒）: 影響範囲の特定
├── Read latency p99 悪化 → キャッシュミス / Hot Key
├── Write latency p99 悪化 → bgsave / ネットワーク
└── 両方悪化 → CPU飽和 / メモリ圧迫

Step 2（2-3分）: 原因カテゴリの絞り込み
├── メモリ起因 → used_memory/maxmemory, evicted_keys, fragmentation_ratio
├── CPU起因 → シャード別CPU, 偏り係数
└── ネットワーク起因 → egress_pending, network I/O

Step 3: 根因特定
├── Hot Key → CPU偏り係数 > 2.0 + 特定シャードCPU高負荷
├── メモリ飽和 → evicted_keys > 0 + fragmentation_ratio > 1.5
└── Proxy問題 → dispatch_failures > 0 + egress_pending 増加
```

---

## 4. Enterprise Proxy 固有の障害パターン

### endpoint_dispatch_failures の増加条件

| シナリオ | 関連指標 |
|---------|---------|
| シャード不達（クラッシュ/再起動中） | `shard_ping_failures` と同時増加 |
| スロットマッピング不整合（リシャーディング中） | `redis_server_forwarding_state > 0` と相関 |
| FD枯渇 | `namedprocess_namegroup_open_filedesc` 急増 |

### endpoint_egress_pending の増加が示す障害

| シナリオ | 特徴 |
|---------|------|
| クライアント受信遅延 | `egress_pending_discarded` も増加 → 深刻 |
| ネットワーク帯域飽和 | `node_network_transmit_bytes_total` が上限付近 |
| HOLブロッキング | `longest_pipeline_histogram` p99 も増加 |

### dmc_ping_failures vs shard_ping_failures

| 指標 | 対象 | 影響 |
|------|------|------|
| `endpoint_ping_failures` | Proxy自体 | クライアント視点のProxy可用性 |
| `dmc_ping_failures` | DMC管理チャネル | 制御プレーン障害。フェイルオーバー遅延 |
| `shard_ping_failures` | 各シャード | データプレーン障害。dispatch_failures の前兆 |

---

## 5. レプリケーション監視

### 状態機械

```
[正常] master_link_status=1, master_sync_in_progress=0
  → レプリカ接続済み、同期完了

[初期同期中] master_link_status=0, master_sync_in_progress=1
  → RDB転送中。600秒超でアラート

[ネットワーク断絶] master_link_status=0, master_sync_in_progress=0
  → 再接続試行中。60秒超でアラート
```

### forwarding_state が非ゼロになる条件
- リシャーディング中のスロット移動
- フェイルオーバー遷移期間
- クラスタトポロジー変更中

### connected_slaves の期待値
- 期待値 = `db_replication_factor - 1`
- 期待値未満が30秒で Warning
- 0 かつ `db_replication_factor > 1` で即 Critical
- `has_quorum == 0` と同時発生 → Split Brain の可能性

---

## 6. 移行監視（シングルノード → Cluster）

### リスクシナリオと検知

| シナリオ | 検知メトリクス | アクション |
|---------|-------------|-----------|
| 移行先メモリ急増 | `used_memory/maxmemory > 0.85`, `evicted_keys > 0` | 移行一時停止、maxmemory引き上げ |
| 接続プール枯渇 | `client_establishment_failures`, `maximal_connections_exceeded > 0` | 切替一時停止、接続プール設定確認 |
| リシャーディング中レイテンシ劣化 | p99 latency > SLO, `forwarding_state > 0` | migrate-batch-size削減 |

### 移行完了判断基準
1. 新クラスタのリクエスト比率 > 99%（24時間維持）
2. 新クラスタの p99 レイテンシ <= 旧環境の 1.2 倍
3. evicted_keys = 0
4. 旧環境リクエスト数が実質 0
5. シャード偏り係数 < 1.3
6. フェイルオーバーテスト完了

---

## 7. 不要メトリクス判定ガイド

### ROF/Flash 未使用時に除外

```
bdb_bigstore_*, bdb_big_*, redis_big_*, redis_rocks_*
node_available_flash_*, node_bigstore_*
redis_server_keys_trimmed
```

### RediSearch 未使用時に除外

```
redis_server_search_*（全て）
```

### Active-Active 未使用時に除外

```
database_syncer_*（全て）
redis_server_repl_touch_bytes
```

### LDAP/CBA 認証未使用時に除外

```
endpoint_*_ldap_*, endpoint_*_cba_*
```

### 低優先度（日常監視不要、調査時のみ参照）

```
redis_server_used_memory_lua          # Lua未使用なら微小
redis_server_pubsub_*                 # Pub/Sub未使用なら不要
redis_server_hashes_items_*           # データ型分布（調査時のみ）
redis_server_lists_items_*
redis_server_sets_items_*
redis_server_zsets_items_*
redis_server_strings_sizes_*
namedprocess_namegroup_thread_cpu_*   # プロセス合計で十分
endpoint_monitor_sessions_count       # 本番でMONITOR使用は性能劣化
```

---

## 8. ダッシュボード設計パターン

### 1枚統合ダッシュボード構成

```
Section 1: ヘルスサマリー（Scorecard × 6）
  → db_status, has_quorum, live_nodes, dispatch_failures, ping_failures
  → 10秒チェック用

Section 2: レイテンシ（時系列 × 4、左右並列）
  → Read/Write p50+p99、prod | prod-cluster 並列
  → SLO直結指標

Section 3: スループット & 接続（時系列 × 4）
  → read/write/other ops/sec、接続数、接続エラー

Section 4: メモリ & キースペース（時系列 + Gauge × 6）
  → メモリ使用率、evicted_keys、キー数、ヒット率、フラグメンテーション

Section 5: シャードヘルス（Cluster専用、時系列 + Scorecard × 6）
  → シャード別メモリ/CPU、偏り係数、forwarding_state、replication

Section 6: ノード & ネットワーク（時系列 + Scorecard × 4）
  → ノードメモリ、ネットワークI/O、egress_pending、証明書残日数

Section 7: 移行監視（一時的、移行完了後に削除）
  → トラフィック比率、リクエスト絶対値、チェックリスト
```

### DB比較方式
- フィルタ切替ではなく**左右固定並列パネル**
- 移行中は同時比較が必須
- 時刻軸を同期させること
- 移行完了後は旧DBパネルを削除するだけで運用ダッシュボードに転用可能
