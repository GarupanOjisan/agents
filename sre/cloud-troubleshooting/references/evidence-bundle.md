# Evidence Bundle

Use this to keep troubleshooting evidence complete, reproducible, and useful for incident review.

## Minimum Bundle

```markdown
## Evidence Bundle
- Time window:
- Timezone:
- User journey / SLO:
- Affected scope:
- Recent changes:
- Metrics:
- Logs:
- Traces:
- Audit/config events:
- Deploy/version data:
- Dependency signals:
- Provider health/status:
- Negative findings:
- Commands/queries run:
- Console/dashboard links:
```

## Collection Rules

- Record the exact time range for every query.
- Keep dimensions attached: region, zone/AZ, version, endpoint, tenant, target group, revision, pod/task, instance.
- Include negative findings such as "no target 5xx in app logs" or "no CloudTrail IAM changes in window".
- Prefer structured logs and exported datasets for high-volume queries.
- Do not run broad expensive queries without narrowing project/account, service, and time range.
- Preserve evidence before destructive mitigation or data restore actions.

## Evidence Quality Bar

Good evidence:

- Directly supports or rules out a hypothesis.
- Has a source and time range.
- Is reproducible by another responder.
- Separates observation from interpretation.

Weak evidence:

- "It looks normal" without a metric or query.
- Dashboard screenshots with no filters/time window.
- Average latency without p95/p99.
- Provider status page alone without workload-local telemetry.

## Timeline Format

```markdown
| Time | Event | Evidence | Decision |
|---|---|---|---|
| 09:42 | p99 latency exceeded SLO | LB metric, service=api, region=... | Start SEV review |
| 09:45 | rollback started | deploy event ... | Mitigate first |
```

## Negative Findings

Negative findings are first-class. Record them when they narrow scope:

- No application logs for LB 5xx.
- No deploy/config change in the incident window.
- No CloudTrail/Cloud Audit Logs IAM change.
- No VPC Flow Logs for expected traffic.
- No replica lag despite read latency.
- No Redis evictions despite cache miss spike.
