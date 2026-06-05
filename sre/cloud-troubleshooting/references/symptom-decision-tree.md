# Symptom Decision Tree

Use this when the starting point is a production symptom rather than a known failing component.

## Triage Inputs

- Time window: first bad minute, last known good, current state.
- Affected scope: all users, one tenant, one region, one AZ/zone, one endpoint, one deploy cohort.
- User journey and SLO: availability, latency, correctness, freshness, durability.
- Recent changes: deploys, config, infrastructure, DNS, IAM, quota, feature flags, batch jobs, traffic spike.
- Entry point: DNS, CDN, load balancer/API gateway, service runtime, queue, datastore, third party.

## Mitigate vs Investigate

Mitigate first when:

- Error budget burn is active.
- The symptom is still user-visible.
- A reversible rollback, traffic shift, feature disablement, capacity increase, or rate limit is available.
- Additional investigation could increase blast radius or delay recovery.

Investigate first when:

- Data corruption, destructive writes, security compromise, or backup integrity is in question.
- The proposed mitigation could lose data or make evidence unrecoverable.
- The symptom has stopped and the main need is prevention.

## Symptom Matrix

| Symptom | First split | Primary evidence | Common mitigation |
|---|---|---|---|
| 5xx spike | Edge/load balancer generated vs backend generated | LB/API gateway status fields, backend logs, request traces | Rollback, traffic shift, disable feature, scale backend |
| Latency spike | Queueing vs execution vs dependency | p50/p95/p99, concurrency, CPU, DB/cache latency, trace spans | Scale, reduce concurrency, shed load, disable slow path |
| Timeout | Connect timeout vs request timeout vs dependency timeout | LB logs, app timeout logs, trace gaps, TCP/network logs | Raise capacity, rollback, circuit break dependency |
| DNS failure | Resolution vs routing vs stale records | DNS query logs, resolver response, TTL/change history | Revert record, lower traffic, alternate endpoint |
| Auth/IAM failure | Identity token vs permission vs org policy | audit logs, auth error codes, recent IAM/policy changes | Revert IAM/config, rotate token, restore service account binding |
| Quota/capacity | Hard quota vs saturation vs autoscaling lag | quota usage, throttling errors, resource metrics, scaling events | Quota increase, failover headroom, scale out, traffic shed |
| Deploy regression | New version only vs all versions | deploy timeline, version labels, canary metrics, error diff | Rollback/canary stop, feature flag off |
| Dependency degradation | Internal vs provider vs third party | per-dependency RED metrics, traces, provider status | Circuit breaker, cache, degrade feature, fail over |
| DB/cache bottleneck | Storage engine/cache signal vs app-side pool | pool metrics, DB/cache metrics, query/command samples | Tune pool, stop batch, route reads, load specific runbook |

## Investigation Order

1. Confirm current impact and whether mitigation is already reducing user-visible symptoms.
2. Compare healthy vs unhealthy dimensions: region, zone, version, endpoint, tenant, dependency, instance class.
3. Check edge/LB/API gateway metrics and logs before assuming application failure.
4. Check runtime health: errors, latency, saturation, restarts, cold starts, autoscaling, queue depth.
5. Check dependencies: DB, cache, queue, third-party, identity, network egress.
6. Check recent changes and audit events.
7. Check provider status only after local evidence identifies provider-managed symptoms or widespread service signals.

## Output Discipline

Every diagnostic step must record:

- Hypothesis.
- Query/command or dashboard.
- Time range.
- Result, including zero-result findings.
- Decision: ruled in, ruled out, or needs follow-up.
