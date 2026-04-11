# Kubernetes 信頼性・運用リファレンス

## 1. クラスタの高可用性

### etcd
- ノード数は奇数（3 or 5）。3ノード: 1障害耐性、5ノード: 2障害耐性
- 専用SSDディスク使用、ノード間レイテンシ 10ms以下
- quota-backend-bytes=8GB、auto-compaction-retention=1h

```bash
# 状態確認
etcdctl endpoint status --cluster -w table
etcdctl endpoint health --cluster
etcdctl alarm list

# バックアップ
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-$(date +%Y%m%d).db
etcdctl snapshot status /backup/etcd-snapshot.db -w table
```

### ノード管理

```bash
# drain（メンテナンス前）
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --grace-period=60

# cordon（スケジューリング対象外、既存Podはそのまま）
kubectl cordon <node>

# uncordon（復帰）
kubectl uncordon <node>
```

**Taint Effect:**
| Effect | 挙動 |
|--------|------|
| NoSchedule | 新規Podをスケジュールしない |
| PreferNoSchedule | 可能ならスケジュールしない |
| NoExecute | 新規拒否 + 既存Pod退避 |

### クラスタアップグレード
- マイナーバージョンは1つずつ
- 廃止APIの事前確認: `pluto detect-all-in-cluster`
- ブルーグリーン: 新ノードプール作成 → cordon/drain → 旧削除

---

## 2. ワークロードの信頼性

### PDB (Pod Disruption Budget)

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
spec:
  maxUnavailable: 1  # 同時に1つまで停止可能
  selector:
    matchLabels:
      app: api-server
```

- replicas=1 で maxUnavailable=0 にしない（drainがブロック）
- `unhealthyPodEvictionPolicy: AlwaysAllow` で CrashLoopBackOff のブロック防止

### リソース設計

```yaml
resources:
  requests:
    cpu: "500m"
    memory: "512Mi"
  limits:
    # CPU limits は設定しない（throttling回避）
    memory: "1Gi"
```

**CPU Throttling:**
- CPU Limits 設定時に CFS スロットリングがレイテンシスパイクの原因に
- 検出: `container_cpu_cfs_throttled_periods_total / container_cpu_cfs_periods_total`
- 対策: CPU Limits を外す、Requests のみ設定

**OOMKill:**
- 検出: `kubectl describe pod` → Last State: OOMKilled
- 防止: Memory Limits を Requests の 1.5〜2 倍
- JVM: `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0`

**QoS クラス:**
| QoS | 条件 | OOM優先度 |
|-----|------|-----------|
| Guaranteed | requests == limits (CPU+Mem) | 最後にkill |
| Burstable | requests < limits | 中 |
| BestEffort | 一切なし | 最初にkill |

本番推奨: Burstable（CPU Limitsなし + Memory Limitsあり）

### プローブ設計

```yaml
startupProbe:        # 起動完了検知。完了まで liveness/readiness 無効
  httpGet: { path: /healthz, port: 8080 }
  failureThreshold: 30
  periodSeconds: 10  # 最大300秒待ち

livenessProbe:       # デッドロック検知 → 再起動
  httpGet: { path: /healthz, port: 8080 }
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:      # トラフィック受信可否 → Endpoints除外
  httpGet: { path: /ready, port: 8080 }
  periodSeconds: 5
  failureThreshold: 3
```

**最重要原則: Liveness で依存サービスをチェックしてはいけない**
→ DB 障害で全 Pod 再起動 → カスケード障害

- Liveness: 自プロセスの生存のみ
- Readiness: 依存サービスのチェックを含めてよい

### トポロジー分散

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
```

---

## 3. ネットワーキング

### DNS (CoreDNS)

**ndots 問題:**
- デフォルト ndots:5 で外部ドメイン解決が最大6回クエリ
- 対策1: 外部ドメインに FQDN（末尾ドット）を使用
- 対策2: `dnsConfig.options: [{name: ndots, value: "2"}]`

### NetworkPolicy

```yaml
# デフォルト拒否 + 必要な通信のみ許可
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
# + CoreDNS へのアクセスは必ず許可（UDP/TCP 53）
```

### Istio

```yaml
# リトライ + タイムアウト（VirtualService）
retries:
  attempts: 3
  perTryTimeout: 3s
  retryOn: "5xx,reset,connect-failure"
timeout: 10s

# サーキットブレーカー（DestinationRule）
outlierDetection:
  consecutive5xxErrors: 5
  interval: 10s
  baseEjectionTime: 30s
  maxEjectionPercent: 50
```

- カナリー: 重み付きルーティング
- ミラーリング: シャドウトラフィックでテスト
- mTLS: STRICT モードで暗号化必須

---

## 4. オートスケーリング

### HPA

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  minReplicas: 3
  maxReplicas: 50
  metrics:
    - type: Resource
      resource: { name: cpu, target: { type: Utilization, averageUtilization: 70 } }
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies: [{ type: Percent, value: 100, periodSeconds: 60 }]
    scaleDown:
      stabilizationWindowSeconds: 300  # 5分安定化
      policies: [{ type: Percent, value: 10, periodSeconds: 60 }]
```

### VPA
- まず `updateMode: "Off"` で推奨値を確認してから `Auto` に切替
- HPA と同じメトリクス（CPU/Memory）で同時使用不可

### Cluster Autoscaler
- Pod Pending でノード追加、低使用率(50%以下 10分)でノード削減
- 過剰プロビジョニング: 低優先度「パッド」Pod で即座スケールアップ

### KEDA
- イベント駆動オートスケーリング（Pub/Sub メッセージ数、Prometheus 等）
- `idleReplicaCount: 0` でスケール to zero

---

## 5. デプロイメント戦略

### Rolling Update

```yaml
strategy:
  rollingUpdate:
    maxSurge: 25%
    maxUnavailable: 0  # 無停止
```

| maxSurge | maxUnavailable | ユースケース |
|----------|---------------|------------|
| 25%/25% | デフォルト、高速 | 一般的なワークロード |
| 1/0 | 無停止 | ダウンタイムゼロ必須 |
| 100%/0 | Blue/Green的 | リソース余裕あり |

**Graceful Shutdown:**
```yaml
lifecycle:
  preStop:
    exec:
      command: ["/bin/sh", "-c", "sleep 15"]
      # kube-proxy のルール更新を待つ
terminationGracePeriodSeconds: 60
```

### Canary（Argo Rollouts）

```yaml
strategy:
  canary:
    steps:
      - setWeight: 5
      - pause: { duration: 5m }
      - analysis: { templates: [{ templateName: success-rate }] }
      - setWeight: 20
      - pause: { duration: 10m }
      - setWeight: 50
```

AnalysisTemplate で Prometheus メトリクスを自動検証。失敗で自動ロールバック。

---

## 6. トラブルシューティング

### Pod 起動失敗の診断フロー

```
Pending → リソース不足? / Taint不一致? / PDB?
ImagePullBackOff → タイポ? / 認証? / レジストリ可用性?
CrashLoopBackOff → kubectl logs --previous / 設定ミス? / OOMKill?
CreateContainerConfigError → ConfigMap/Secret 存在確認
```

### 基本コマンド

```bash
kubectl get pods -o wide
kubectl describe pod <pod>
kubectl logs <pod> --previous        # CrashLoopBackOff時
kubectl logs <pod> --all-containers
kubectl get events --sort-by='.lastTimestamp'
kubectl top nodes / pods
```

### ノード障害のタイムライン
```
0s: ノード応答不能
40s: NotReady に変更
5m: unreachable Taint 付与、Pod 退避開始
```

### リソース枯渇

```bash
kubectl top nodes
kubectl describe node <node> | grep -A 20 "Allocated resources"
kubectl get pods -o json | jq '.items[] | select(.status.containerStatuses[]?.lastState.terminated.reason == "OOMKilled")'
```

### ネットワーク診断

```bash
# DNS
kubectl run dnstest --image=busybox --rm -it -- nslookup <service>
# Endpoints
kubectl get endpoints <service>
# NetworkPolicy
kubectl get networkpolicy -n <ns>
# パケットキャプチャ
kubectl debug <pod> -it --image=nicolaka/netshoot -- tcpdump -i eth0 port 8080
```

### Ephemeral Debug Container

```bash
# 実行中Podにデバッグコンテナ追加
kubectl debug <pod> -it --image=nicolaka/netshoot --target=<container>
# ノードデバッグ
kubectl debug node/<node> -it --image=busybox
```

---

## 7. セキュリティ

### RBAC
- 最小権限の原則
- グループベースの権限管理
- `kubectl auth can-i --list --as=user -n namespace` で権限確認

### Pod Security Standards
- `privileged`: 制限なし
- `baseline`: 基本制限（hostNetwork禁止、特権コンテナ禁止）
- `restricted`: 厳格（non-root必須、全Capabilities削除）

```yaml
# Namespace ラベルで適用
pod-security.kubernetes.io/enforce: restricted
```

### External Secrets Operator
- GCP Secret Manager / Vault からの自動同期
- `refreshInterval: 1h` で定期同期

---

## 8. GitOps (ArgoCD)

```yaml
syncPolicy:
  automated:
    prune: true       # Gitから削除されたリソースを自動削除
    selfHeal: true    # ドリフトを自動修復
ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers: [/spec/replicas]  # HPA管理のため無視
```

- AppProject で権限分離
- ドリフト検出と自動修復
- リトライポリシーで一時的な障害に対応

---

## 9. 監視

### kube-state-metrics 重要メトリクス

```promql
# CrashLoopBackOff
rate(kube_pod_container_status_restarts_total[15m]) * 60 * 15 > 0

# レプリカ不一致
kube_deployment_status_replicas_available < kube_deployment_spec_replicas

# HPA 上限到達
kube_horizontalpodautoscaler_status_current_replicas == kube_horizontalpodautoscaler_spec_max_replicas

# ノード NotReady
kube_node_status_condition{condition="Ready",status="true"} == 0

# PDB 違反
kube_poddisruptionbudget_status_current_healthy < kube_poddisruptionbudget_status_desired_healthy
```

### cAdvisor メトリクス

```promql
# CPU Throttling 率（25%以上で見直し）
container_cpu_cfs_throttled_periods_total / container_cpu_cfs_periods_total

# メモリ使用率（Limits比、80%以上でOOMリスク）
container_memory_working_set_bytes / kube_pod_container_resource_limits{resource="memory"}
```

### PV 枯渇予測

```promql
# 4日以内に枯渇予測
kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes < 0.15
AND predict_linear(kubelet_volume_stats_available_bytes[6h], 4*24*3600) < 0
```

---

## 10. 日次ヘルスチェック

```bash
# NotReady ノード
kubectl get nodes --no-headers | grep -v " Ready "

# 異常 Pod
kubectl get pods -A --field-selector status.phase!=Running,status.phase!=Succeeded

# 高リスタート Pod
kubectl get pods -A -o json | jq '.items[] | select(.status.containerStatuses[]?.restartCount > 5)'

# PDB 違反
kubectl get pdb -A -o json | jq '.items[] | select(.status.currentHealthy < .status.desiredHealthy)'

# HPA 上限
kubectl get hpa -A -o json | jq '.items[] | select(.status.currentReplicas == .spec.maxReplicas)'
```
