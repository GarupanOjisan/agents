# Spanner で最低限実装で気をつけること

> 他のドキュメントも読んでおくべきだが、最低限気をつけてほしい内容をまとめた。
> 詳細は各リンク先を参照。事故頻度順に並べている。

## 初級編

### ルール 1: トランザクション内で外部サービスに書き込みしないこと

Spanner + Go では:

- **RW トランザクションが失敗することがある**（MySQL より失敗確率は高い。アプリケーション起因でエラーにしなくても、Spanner 起因で abort される）
- **RW トランザクションがリトライされることがある**（RO はリトライされない）

どちらもトランザクション内での変更は rollback されるが、トランザクション内で Redis に保存処理をしていたりすると Redis にだけデータが保存されてしまうケースや、Redis への加算が重複して行われてしまうケースが発生する。

よって、RW トランザクション内で以下のサービスやミドルウェアへの書き込み・publish はしない:

- Redis
- Google Pub/Sub
- NATS

**悪い例**:

```go
// ※ i.db, transactable.Transaction, BeginRwTransaction, AfterCommit は
//   ColorSing 内製ラッパー（公式 cloud.google.com/go/spanner API ではない）
err := i.db.BeginRwTransaction(ctx, func(ctx context.Context, txn transactable.Transaction) error {
    following = models.NewFollowing(userID, targetUserID, t, t)
    if err := i.followingRepository.Create(ctx, txn, following); err != nil {
        return err
    }

    // (NG) RW 内なので、トランザクションが Rollback されても通知されてしまう
    //      またトランザクションが成功しても、通知が 2 回以上送られてしまうことがある（リトライされたせいで）
    return i.publishFollowEventOnFirstTime(ctx, txn, followedHistory, following, onAirLive, userID, targetUserID, t)
})
```

**良い例 1**（トランザクション外で publish）:

```go
err := i.db.BeginRwTransaction(ctx, func(ctx context.Context, txn transactable.Transaction) error {
    following = models.NewFollowing(userID, targetUserID, t, t)
    return i.followingRepository.Create(ctx, txn, following)
})
if err != nil {
    return err
}

// (OK) トランザクションの外なので 1 回のみ実行される
err = i.publishFollowEventOnFirstTime(ctx, ...)
```

**良い例 2**（`AfterCommit` を使う）:

```go
err := i.db.BeginRwTransaction(ctx, func(ctx context.Context, txn transactable.Transaction) error {
    following = models.NewFollowing(userID, targetUserID, t, t)
    if err := i.followingRepository.Create(ctx, txn, following); err != nil {
        return err
    }

    // (OK) AfterCommit はトランザクションが成功したあとに処理を実行してくれる
    //      ただし AfterCommit はプロセスクラッシュで消失するため、
    //      金銭・監査用途は Change Streams を検討する（./change-streams.md）
    return txn.AfterCommit(func(ctx context.Context) error {
        return i.publishFollowEventOnFirstTime(ctx, txn, followedHistory, following, onAirLive, userID, targetUserID, t)
    })
})
```

### ルール 2: RW トランザクションの範囲を狭くして、なるべく RO を使う

※ RW = ReadWrite トランザクション、RO = ReadOnly トランザクション

Spanner は RW 内で取得したレコードを必ず**共有ロック**する。共有ロックを取ったレコードは他のトランザクションから書き込みできなくなるので、トランザクションが abort しやすくなる。

よって Spanner からデータを取得するときは、なるべく RO を使う。

ただし RO から取ったデータは以下の注意点がある:

- データが少し古いことがある
  - 必ず最新のデータを参照したいときは RW で取得する
- 取得したデータをロックできない
  - ロックしたいときは RW で取得する

詳細は [ロックについて意識する](./locking.md) と [Stale Read の使い分け](./stale-reads.md) を参照。

**悪い例**:

```go
// ※ i.db, transactable.Transaction, BeginRwTransaction は
//   ColorSing 内製ラッパー（公式 cloud.google.com/go/spanner API ではない）
err := i.db.BeginRwTransaction(ctx, func(ctx context.Context, txn transactable.Transaction) error {
    // ライブを取得
    // (NG) ライブレコードのロックを取ってしまってるので NG。ここはロックを取る必要がない
    live, err = i.liveRepository.Find(ctx, txn, liveID)
    if err != nil {
        return err
    }

    // コメントを作成
    liveComment = models.NewLiveComment(
        live.liveID,
        userID,
        mentionUserID,
        []byte(body),
    )
    if err = i.liveCommentRepository.Create(ctx, txn, liveComment); err != nil {
        return err
    }
    return nil
})
```

**良い例**:

```go
var live *models.Live
err := i.db.BeginRoTransaction(ctx, func(ctx context.Context, txn transactable.Transaction) error {
    // ライブを取得
    // (OK) RO 内なのでロックを取らずに取得できる
    live, err = i.liveRepository.Find(ctx, txn, liveID)
    return err
})

err = i.db.BeginRwTransaction(ctx, func(ctx context.Context, txn transactable.Transaction) error {
    // コメントを作成
    liveComment = models.NewLiveComment(
        live.liveID,
        userID,
        mentionUserID,
        []byte(body),
    )
    return i.liveCommentRepository.Create(ctx, txn, liveComment)
})
```

### ルール 3: 必要に応じて悲観ロックを取る（Redis ベース）

Spanner は**楽観ロック方式**。MySQL などの悲観ロック方式とは異なるので注意が必要。

Spanner は楽観ロックなので、複数トランザクションが競合してしまったときどちらかのトランザクションが失敗する。Go の SDK が失敗後に複数回リトライしてくれるが、一定回数リトライしても成功しないと失敗のままトランザクションが終了する。

楽観ロック＋リトライだと、複数のユーザーが Read や Write するレコードにアクセスすると競合して失敗しやすいので、悲観ロックを取ることで他のユーザーがレコードにアクセスしているときは他のユーザーを待機させる。

**悲観ロックを取らないといけない例**:

- リスナーが、ライバーの情報を読み書きする（複数のリスナーがライバーのロックを取り合うため）
- リスナーが、配信の情報を読み書きする（複数のリスナーが配信情報のロックを取り合うため）

**悲観ロックを取る例**:

```go
// ※ i.db, transactable.Transaction, BeginRwTransactionWithUserLock は
//   ColorSing 内製ラッパー（公式 cloud.google.com/go/spanner API ではない）
// BeginRwTransactionWithUserLock を使うと悲観ロックが取れる
// liverUserID に対してロックしている。同じ liverUserID のトランザクションはロック解放まで待機
err = i.db.BeginRwTransactionWithUserLock(ctx, i.redisClient, liverUserID,
    func(ctx context.Context, txn transactable.Transaction) error {
        // ...
    })
```

なお ColorSing では Redis を使って悲観ロックを実現している。**TTL 設計・障害時方針・デッドロック回避などの落とし穴は** [ロックの挙動について](./locking.md) の「Redis 悲観ロックの運用上の落とし穴」節を必ず確認すること。

### ルール 4: テーブルに適切な TTL を設定する

※ TTL = 有効期限

Spanner に限らず一般的に RDB はテーブル内のレコード数が多いほどクエリが遅くなる（インデックスを適切に設定したとしても）。Spanner はテーブルに TTL を設定することで古いレコードを自動削除できる。

アプリケーション側から参照されなくなったレコードが削除されるように TTL を設定する。

| ケース | TTL |
|--------|-----|
| アプリ側で CREATE, DELETE を適切に行うテーブル（例: `OnAiredLives`） | 不要 |
| アプリ側で READ を行わない履歴テーブル（例: `UserCoinBalanceInOutHistories`） | 不要 |
| アプリ側で READ があり、かつ DELETE を行わないテーブル | **必要**（レコードが無限に増えて READ が重くならないように） |

無限にレコードを遡れるなどの仕様で TTL が設定できない場合は、仕様側で参照するレコードの期限を決めるよう PdM と調整する。例: アプリ上で過去データを参照する仕様を、1ヶ月や1年の遡及上限に変更する。

**TTL の設定例**:

```sql
-- 有効期限 1 日の TTL を設定
ALTER TABLE PubsubMessages ADD ROW DELETION POLICY (OLDER_THAN(CreatedAt, INTERVAL 1 DAY));
```

※ TTL を 1 日としても厳密に 1 日経ったら消えるわけではない。1 日以上経ったら Spanner が任意のタイミングで消す。

> **⚠️ 警告: バックアップ復元後の TTL**
> Spanner のバックアップからデータベースを復元すると、**ROW DELETION POLICY（TTL ポリシー）は自動的にドロップ（削除）される**（公式仕様）。何もしないと TTL が効かず古いデータが溜まり続けるため、復元後は以下を必ず実施:
> 1. `SPANNER_SYS.ROW_DELETION_POLICIES` で TTL ポリシーの有無を確認（復元直後は空のはず）
> 2. `ALTER TABLE ... ADD ROW DELETION POLICY (...)` でポリシーを**再定義**する（REPLACE ではなく新規 ADD）
> 3. 再定義直後は滞留していた古いデータの大量削除が走るので、削除負荷が本番 CPU を圧迫しないかを監視
> 詳細は [バックアップ運用ポリシー](./backup-policy.md) および [公式ドキュメント](https://cloud.google.com/spanner/docs/ttl/manage-ttl) を参照。

### ルール 5: 大量 DML は Partitioned DML を使う

通常の RW トランザクション内の DML は**1 トランザクションあたり 80,000 ミューテーション**の上限がある。数万行を超える UPDATE / DELETE は **Partitioned DML** を使う。

**選択基準**:

| 更新行数 | 選ぶ手段 |
|----------|----------|
| 〜数百行 | 通常 RW TX 内の DML |
| 数百〜数万行 | 通常 DML + バッチ分割 |
| **数万行以上** | **Partitioned DML**（[partitioned-dml.md](./partitioned-dml.md)） |
| 時系列での自動削除 | TTL (ROW DELETION POLICY) |

**Partitioned DML の必須要件**: 冪等性。`Balance = Balance + 100` のような累積更新は**絶対に使えない**。詳細は [Partitioned DML](./partitioned-dml.md) を参照。

### ルール 6: パラメータバインディングを必須にする

文字列結合で SQL を組み立てると:

1. **SQL インジェクション脆弱性**
2. **クエリプランキャッシュが効かない**（パラメータごとに別クエリとして扱われるため、毎回プラン生成で CPU を消費）

**悪い例**:

```go
// NG: SQL インジェクション + プランキャッシュミス
stmt := spanner.Statement{
    SQL: fmt.Sprintf("SELECT * FROM Users WHERE UserId = '%s'", userID),
}
```

**良い例**:

```go
// OK: パラメータバインディング
stmt := spanner.Statement{
    SQL: `SELECT * FROM Users WHERE UserId = @userId`,
    Params: map[string]interface{}{
        "userId": userID,
    },
}
```

動的な `IN` 句も配列バインディングで対応する:

```go
stmt := spanner.Statement{
    SQL: `SELECT * FROM Users WHERE UserId IN UNNEST(@userIds)`,
    Params: map[string]interface{}{
        "userIds": userIDs, // []string
    },
}
```

### ルール 7: 本番クリティカルパスの TX/Request にタグを付ける

Transaction Tag / Request Tag がないと `SPANNER_SYS` ビューで障害原因を特定できない。本番に出る RW トランザクションと重いクエリには必ずタグを付ける。

詳細・命名規約・Go コード例は [Transaction Tag / Request Tag](./tags.md) を参照。

**最小限の例**:

```go
// ※ ColorSing 内製ラッパー
err := i.db.BeginRwTransactionWithTag(ctx,
    "service=api,route=POST_/live/comment",
    func(ctx context.Context, txn transactable.Transaction) error {
        // ...
    })
```

---

## 中級編

### ホットスポットを避ける

主キーの先頭にはとりあえず **UUIDv4** を使っておけばよい。

Cloud Spanner は分散データベースで、PK の値にしたがってデータの格納場所を決定する。したがって単調増加な値を主キーの先頭に使用したり、多くのユーザーが特定のキーを参照すると、特定の場所に書き込み・読み込みが集中して性能劣化を引き起こす。

特殊なケースで困ったら公式ドキュメントを参照する。論理シャードやビット順逆転はたまに使うケースはある。

参考: [プライマリキーでホットスポットを回避する | Spanner](https://cloud.google.com/spanner/docs/schema-design?hl=ja#primary-key-prevent-hotspots)

#### セカンダリインデックスも気をつける

セカンダリインデックスは Cloud Spanner だと通常のテーブルとして扱われる。したがってインデックスの先頭に単調増加するような値や、多くのユーザーが同時に参照するような値（`LiveId` など）を選ぶとホットスポットになり得る。セカンダリインデックスについてもホットスポットを意識する。

### ロックについて意識する

簡単に言うと「同じキーに同時刻にアクセスしそうだな」ってときは意識する。

ロックが競合した場合、優先度によって待つ（wait）か、中断（abort）させてロックを奪う。優先度は以下の考え方で決まる:

- トランザクションの最初のオペレーションが早い方が高い
- 一度リトライされたトランザクションは優先度が上がる
- 明示的に指定することも可能

ロックについて詳しくは [ロックについて意識する](./locking.md) を参照。

#### 競合時の挙動

ロックが競合して abort されたトランザクションは各言語のライブラリによってリトライされる。したがって、例えばトランザクションの外の slice に append するような処理が意図せずリトライされることに注意。

### Stale Read の使い分け

読み取りには Strong / Bounded Staleness / Exact Staleness の 3 種類がある。**金銭・認証以外はなるべく Stale Read** を使ってリーダーレプリカ負荷を下げる。

ColorSing での使い分け表、コード例、PR レビュー観点は [Stale Read の使い分け](./stale-reads.md) を参照。

**Strong Read 必須**: コイン / ダイヤ残高、換金、BAN 判定
**Exact Staleness 15〜30 秒で十分**: プロフィール、ランキング、ホームフィード
**Exact Staleness 60 秒以上**: ダッシュボード、分析

### クエリプランは必ず見る

新しいクエリを発行するときは必ず Cloud Console からクエリプランを見る。見るべきポイントは以下:

- **スキャン行数**: フルスキャンになっていないか
- **複数のノードを横断したスキャンになっていないか**: `distributed union` 演算子があれば横断している

参考: [クエリ実行プラン | Spanner](https://cloud.google.com/spanner/docs/query-execution-plans?hl=ja)
