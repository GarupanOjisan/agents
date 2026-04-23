# クエリビルダの選定

## 背景

複数のパラメータで Spanner にクエリを発行するような場合、「A の条件は必要だけど B は今回は不要」みたいなことがある。Go のコードで言うと下記のような実装になる。

```go
var whereParams []string

if param.A != nil {
    whereParams = append(whereParams, "A = @paramA")
}

if param.B != nil {
    whereParams = append(whereParams, "B = @paramB")
}

sql := "SELECT * FROM Singers"
if len(whereParams) > 0 {
    sql += " WHERE " + strings.Join(whereParams, " AND ")
} else {
    sql += " WHERE true"
}
```

これだと最終的なクエリの見通しが悪いので、何かクエリに問題があっても気付くことが難しい。実装者自身も間違えるし面倒くさい。

そこでクエリビルダの導入を目標に、Spanner 向けに適切なクエリビルダを選定したい。

## 前提条件

現在 Spanner への接続には `database/sql` パッケージを利用している。これは Google Cloud から GA されたもので自信を持って使ってよい。`database/sql` での実装が進んでいるので、既存の実装からの変更が少なく取り入れられるものを選びたい。

## 候補

### 公式情報

まず Google からの情報を漁ったが、Go 言語で広く知られている Spanner 用のクエリビルダは存在しなさそう。

### GORM

良くも悪くも有名だが、公式には Spanner をサポートしていないので第一候補からは外す。

### goqu

star 数は多いが Spanner はサポートしていない。

### memeduck

[memeduck](https://github.com/genkami/memeduck) は Spanner のクエリビルダを謳っているので検証対象。

### spansql-query-builder

Spanner のクエリビルダを謳っているので検証対象だったが、非採用。

## 結論

**`memeduck` 一択**だった。

`memeduck` は `JOIN` が使えないが、インターリーブしている子テーブルは **サブクエリで取った方がパフォーマンスが良い**ので、これを機に JOIN を制限しても良い。

## ColorSing での運用

- ORM 的な役割: [mercari/yo](./query-template-library.md) でモデルと定型クエリ生成
- 動的なクエリ組み立て: `memeduck`
- 接続: `database/sql`
