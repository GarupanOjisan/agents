# Google Cloud WAF Reliability / Operational Excellence

Source references:
- Google Cloud Well-Architected Framework Reliability: https://docs.cloud.google.com/architecture/framework/reliability
- Google Cloud Well-Architected Framework Operational Excellence: https://docs.cloud.google.com/architecture/framework/operational-excellence
- Google public Agent Skills repository: https://github.com/google/skills

Use this reference when reviewing a Google Cloud workload for reliability, operability, or production readiness.

## Reliability Review Frame

Evaluate reliability from user-visible outcomes first. Infrastructure health is supporting evidence, not the SLO itself.

Core questions:
- What user journey is protected by this service?
- What SLI captures user pain directly: success rate, latency, freshness, durability, correctness, or availability?
- What SLO is realistic for the product tier and business impact?
- What error budget policy changes release velocity when reliability regresses?
- What failure modes are expected, and which ones must degrade gracefully?
- What RTO/RPO is required for each data class?

## Architecture Checklist

- Define SLIs and SLOs before adding alerts.
- Remove single points of failure across zones, regions, control planes, and critical dependencies.
- Use horizontal scalability where practical: GKE HPA/VPA, Cloud Run autoscaling, Spanner processing units, Redis shard planning.
- Make health checks reflect real dependency readiness, not only process liveness.
- Use retries with budgets, exponential backoff, jitter, deadlines, circuit breakers, and idempotency keys.
- Prefer graceful degradation for non-critical features over cascading failure.
- Test rollback, failover, backup restore, and data corruption recovery before incidents.
- Use blameless postmortems with concrete Prevent / Detect / Mitigate follow-up actions.

## Operational Excellence Checklist

- Every production service has an owner, SLO, dashboard, runbook, and escalation path.
- Alerts are symptom-based and actionable. Page only when a human must act now.
- Runbooks include validation commands, rollback commands, expected outputs, and escalation criteria.
- Release mechanisms support safe rollout: canary, progressive delivery, feature flags, and fast rollback.
- Infrastructure changes are versioned, reviewed, and drift-detected.
- Toil is measured and reviewed. Repeated manual actions become automation candidates.
- Cost and reliability trade-offs are explicit. Do not silently lower redundancy to reduce spend.

## Incident Response Defaults

1. State the current impact in user terms.
2. Identify the fastest mitigation path: rollback, traffic shift, dependency disablement, rate limiting, or feature flag.
3. Assign incident roles: commander, comms, operations, scribe.
4. Keep a timeline with exact timestamps and commands.
5. After mitigation, separate root cause analysis from customer-impact recovery.

## Output Template

Use this shape for reviews:

```markdown
## Summary
[One paragraph: risk posture and most important recommendation]

## SLO / User Impact
- SLI:
- SLO:
- Error budget policy:

## Key Risks
| Severity | Risk | Evidence | Recommendation |
|---|---|---|---|

## Resilience Plan
- Prevent:
- Detect:
- Mitigate:
- Recover:

## Next Actions
1. [Owner] [Action] [Due date / priority]
```
