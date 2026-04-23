# セッションプール

Spanner クライアントは内部にセッションプールを持つ。ColorSing のような高 QPS 環境では設定ミスがリーク / 枯渇に直結する。

## ColorSing 推奨設定

```go
import "cloud.google.com/go/spanner"

client, err := spanner.NewClientWithConfig(ctx, dbPath, spanner.ClientConfig{
    SessionPoolConfig: spanner.SessionPoolConfig{
        MinOpened:           100,  // Pod 起動直後の preload
        MaxOpened:           400,  // Pod あたりの上限
        WriteSessions:       0.2,  // RW 向けに確保する割合
        HealthCheckInterval: 30 * time.Second,
    },
})
```

### 上限算定ルール

```
Pod 台数 × MaxOpened <= DB セッション上限（10,000 / ノード）
```

公式制限は「**10,000 sessions / ノード**」なので、インスタンスのノード数に応じて全体上限が決まる。例えば 10 ノードなら 100,000 セッションまで取得可能。

**計算例**（5 ノードインスタンス、API Pod 20 台、ワーカー Pod 10 台の場合）:

- 全体上限: `5 × 10,000 = 50,000`
- API: `20 × 400 = 8,000`
- ワーカー: `10 × 200 = 2,000`
- 合計 10,000、上限に対して 20% 使用（十分な余裕）

スパイク時の HPA で Pod が 1.5 倍になる前提で、平常時は上限の **60〜70% に収める**。ノードをオートスケーラーで変動させる場合、**最小ノード数を基準**に算定する。

## `database/sql` ドライバ使用時の注意

`github.com/googleapis/go-sql-spanner` を使う場合:

```go
db, err := sql.Open("spanner", dbPath)
db.SetMaxOpenConns(400)    // セッションプールの MaxOpened と一致させる
db.SetMaxIdleConns(100)    // MinOpened と一致
db.SetConnMaxLifetime(0)   // 0 = 再利用上限なし（Spanner は長寿命セッション推奨）
```

**落とし穴**:

- `SetMaxOpenConns` と Spanner 側 `MaxOpened` の**両方**を合わせないとどちらかで詰まる
- `SetConnMaxLifetime` を短く設定するとセッション作り直しが頻発してレイテンシ悪化

## セッションリーク検出

### `db.Stats()` を定期収集

```go
stats := client.Stats()
// stats.NumOpenedSessions  // 現在オープン中
// stats.NumInUseSessions   // 利用中
// stats.NumIdleSessions    // アイドル
```

### OpenTelemetry メトリクス

Spanner クライアントは以下をエクスポート:

- `spanner.googleapis.com/client/session_count`（by `session_type`）
- `spanner.googleapis.com/client/get_session_timeouts_count`

**アラート例**:

- `NumInUseSessions / MaxOpened > 0.9` が 5 分継続 → 枯渇注意
- `get_session_timeouts` が発生 → 即座にアラート（= リクエスト失敗発生中）

### リーク検出

ロングラン TX はログに警告を出す設定を入れる:

```go
SessionPoolConfig: spanner.SessionPoolConfig{
    TrackSessionHandles: true,  // リーク時にスタックトレースを出す
}
```

## Multiplexed Sessions

1 セッションで複数同時リクエストを処理できる新機能。**読み取り系**で段階導入中。

- RO: 既定で利用開始可（SDK バージョン要確認）
- RW: プレビュー段階、本番導入は慎重に
- ColorSing: **RO のみ有効化**を推奨（2026 時点）

```go
SessionPoolConfig: spanner.SessionPoolConfig{
    enableMultiplexSession: true,  // 実装は SDK バージョンで API が異なる
}
```

## GKE からの接続

- **Workload Identity 必須**: SA キーファイルは使わない
- ServiceAccount に `roles/spanner.databaseUser` を付与
- Node プールの Workload Identity を有効化
- Pod spec で `serviceAccountName` を指定し、KSA を GSA にバインド

```yaml
# ServiceAccount 例
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-ksa
  annotations:
    iam.gke.io/gcp-service-account: spanner-api@PROJECT.iam.gserviceaccount.com
```

SA キーを Secret に置くパターンは**禁止**（漏洩時の無効化ができない）。

## 参考

- [セッションの管理 | Spanner](https://cloud.google.com/spanner/docs/sessions)
- [Go クライアントライブラリ](https://pkg.go.dev/cloud.google.com/go/spanner)
