# Mitigation Playbook

Use this when the service is still degraded or when choosing between rollback, traffic shift, rate limiting, capacity, dependency isolation, or data-protection actions.

## Mitigation Principles

1. Restore user-visible behavior before proving root cause.
2. Prefer reversible, low-blast-radius actions.
3. Define validation before acting.
4. Avoid actions that destroy evidence or risk data safety unless impact demands it.
5. Stop the mitigation if validation worsens or a safety condition triggers.

## Mitigation Options

| Option | Use when | Watch-outs | Validation |
|---|---|---|---|
| Rollback | recent deploy/config likely correlated | DB migrations, schema compatibility, cached state | error rate/latency returns to baseline |
| Traffic shift | one region/AZ/cell/version is unhealthy | target capacity and quota in destination | healthy destination SLO, no saturation |
| Feature disablement | one feature path causes impact | partial user impact, hidden dependencies | affected endpoint recovers |
| Rate limiting / load shedding | overload or dependency saturation | fairness, paid/customer impact | queue depth and p99 improve |
| Scale out/up | capacity saturation or autoscaling lag | quota, warmup, cost, downstream pressure | saturation drops without error spike |
| Circuit breaker | dependency degradation | stale data, degraded UX | main journey recovers, dependency load falls |
| Stop batch/job | background workload competes with user path | data freshness, retry storm | resource pressure drops |
| Failover | regional/AZ/provider component impaired | data lag, quota, cold capacity | writes/reads validated in target |
| Data protection freeze | corruption/destructive writes suspected | availability impact | no additional bad writes |

## Decision Template

```markdown
## Mitigation Decision
- Action:
- Why now:
- Expected customer effect:
- Blast radius:
- Data safety risk:
- Evidence preserved:
- Operator:
- Start time:
- Abort condition:
- Validation metric/log:
- Follow-up owner:
```

## Safety Gates

Do not proceed without explicit owner approval when:

- The action can lose data or widen corruption.
- The action requires cross-region failover with possible stale data.
- The action changes IAM/security posture.
- The action affects all tenants rather than an isolated cohort.
- The action hides evidence needed for security or data-loss investigation.
