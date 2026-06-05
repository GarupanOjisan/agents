# Google Cloud Service Troubleshooting

Source references:
- Cloud Run troubleshooting: https://docs.cloud.google.com/run/docs/troubleshooting
- Cloud Run troubleshooting overview: https://docs.cloud.google.com/run/docs/troubleshooting/overview
- Cloud Run monitoring and logging overview: https://docs.cloud.google.com/run/docs/monitoring-overview
- Cloud Load Balancing metrics: https://docs.cloud.google.com/load-balancing/docs/metrics
- Load balancer SLI metrics: https://cloud.google.com/stackdriver/docs/solutions/slo-monitoring/sli-metrics/lb-metrics

Use this for Google Cloud services where the symptom is service-level 5xx, latency, timeout, auth/IAM failure, quota, deploy regression, or dependency degradation.

## Evidence Sources

| Layer | Primary evidence |
|---|---|
| Cloud Load Balancing / API edge | request count, response code class, backend latency, health check state, backend service logs |
| Cloud Run | request logs, revision labels, instance ID, request latency, container startup, CPU/memory/concurrency, revision rollout |
| GKE | workload events, pod restarts, readiness/liveness probes, HPA/VPA, node pressure, ingress/backend health |
| Cloud SQL | connection count, CPU, I/O, lock waits, slow queries, replica lag, maintenance/failover events |
| Pub/Sub / queues | oldest unacked message age, ack deadline expirations, publish/pull errors, subscriber saturation |
| IAM/auth | Cloud Audit Logs, service account changes, org policy, token/audience errors |
| Quota/capacity | quota usage, throttling errors, autoscaler limits, regional capacity signals |
| Network | VPC Flow Logs, firewall logs, Cloud NAT logs, Connectivity Tests; use the `sre` skill reference `references/google-cloud-network-observability.md` |

## GCP Initial Flow

1. Identify the user journey and entry point: Cloud Load Balancer, API Gateway, Cloud Run URL, GKE ingress, or internal service.
2. Compare LB/API edge status codes against backend logs:
   - edge generated 5xx: inspect health checks, backend availability, timeout, connection errors.
   - backend generated 5xx: inspect service logs, traces, dependency spans, and recent release.
3. Compare dimensions: region, zone, revision, backend service, endpoint, tenant.
4. Check revision/deploy timeline before deep infrastructure debugging.
5. Check service saturation: concurrency, CPU, memory, restarts, autoscaling ceiling, cold starts, queue depth.
6. Check dependency spans and managed service metrics.
7. If network-specific evidence appears, load the `sre` skill reference `references/google-cloud-network-observability.md`.

## Symptom Playbooks

### 5xx

- Split by `response_code_class`, backend service, revision, and endpoint.
- Confirm whether errors appear in application logs. If LB shows 5xx without app logs, suspect edge/backend connectivity, health checks, timeouts, or request never reaching runtime.
- Check health check logs and backend service health for Cloud Load Balancing.
- Check Cloud Run/GKE revision rollout and recent config changes.
- Mitigate with rollback, traffic split, backend drain, or feature disablement.

### Latency

- Split latency by edge/LB latency, backend latency, application span latency, and dependency latency.
- Check p50/p95/p99, not only averages.
- For Cloud Run, check concurrency, CPU allocation behavior, instance startup, memory pressure, and revision-specific latency.
- For GKE, check pod CPU throttling, node pressure, HPA lag, readiness probe flaps, and service mesh retries.
- Mitigate with traffic shift, lower concurrency, scale out/up, stop slow batch, or dependency circuit breaker.

### Timeout

- Determine where the timeout is enforced: client, load balancer, Cloud Run/GKE service, app HTTP client, database, cache, or third party.
- Look for trace gaps and incomplete application logs.
- Check network egress, proxy configuration, DNS, and Cloud NAT if outbound calls fail or stall.
- Mitigate by rollback, capacity action, failover, dependency disablement, or temporary timeout tuning only when safe.

### IAM / Auth

- Check Cloud Audit Logs for service account, IAM policy, org policy, workload identity, secret, and key changes.
- Compare failing principal, resource, audience, and permission against last-known-good.
- Mitigate by reverting the exact binding/config change or switching to a known-good service account only with security approval.

### Quota / Capacity

- Check quota usage and throttling errors before assuming application regression.
- Confirm autoscaler max settings and regional capacity dependencies.
- Validate failover headroom before shifting traffic.
- Mitigate with quota increase, scale-out, traffic shed, or feature degradation.

## GCP Output Additions

Add these fields to the standard troubleshooting output:

```markdown
## GCP Evidence
- Project / region / service:
- Entry point:
- Revision / deployment:
- LB/API edge signal:
- Runtime signal:
- Dependency signal:
- Audit / config changes:
- Quota / capacity:
```
