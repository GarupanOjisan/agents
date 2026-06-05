# Production Readiness / Launch Review

Source references:
- Google SRE Production Readiness Review engagement model: https://sre.google/sre-book/evolving-sre-engagement-model/
- Google SRE Launch Coordination Checklist: https://sre.google/sre-book/launch-checklist/
- Google SRE reliable product launches: https://sre.google/sre-book/reliable-product-launches/

Use this reference for new services, major launches, migrations, infrastructure changes, new dependencies, large traffic events, or production ownership transfers.

## Review Principle

Production readiness is not a one-time checklist. It is a review of whether the service can be safely operated, changed, debugged, and recovered by the owning team.

## Required Inputs

- Architecture diagram and critical request flows.
- Owner, on-call team, escalation path, and dependency owners.
- User journeys and SLOs.
- Expected traffic, launch spike, growth forecast, and capacity model.
- Dependency list with failure behavior.
- Deployment, rollback, and emergency control plan.
- Runbooks and dashboards.
- Data backup, restore, and DR plan.

## PRR Checklist

### Architecture and Dependencies

- Critical path and non-critical path are identified.
- Dependency owners and escalation paths are known.
- Dependency failures have timeout, retry, circuit breaker, and graceful degradation behavior.
- The service does not depend on batch-only systems for live user traffic.
- Shared infrastructure capacity is reviewed with the owning teams.

### SLO / Monitoring / Alerting

- User-visible SLIs and SLOs are defined before alerting.
- Alerts are symptom-based and actionable.
- Dashboards show user impact, dependency health, saturation, and recent changes.
- Monitoring the monitoring is in place for critical signal paths.
- Error budget policy has release consequences.

### Capacity / Quotas / Performance

- Capacity model covers normal load, launch spike, failover, and 6-month growth.
- Load test results are recorded with bottlenecks and max latency.
- Quotas and fixed constraints have headroom for failover.
- Autoscaling limits, warmup time, and cold-start behavior are understood.

### Change and Launch Controls

- Builds are repeatable.
- Rollouts are staged and canary-capable.
- Rollback is tested and faster than forward-fix for common failures.
- Feature flags or kill switches exist for risky paths.
- Launch timing avoids unnecessary operational risk.

### Emergency Controls

- Runbooks include validation commands, expected output, rollback, and escalation.
- On-call has access and knows break-glass procedure.
- Incident roles are known.
- Manual override controls are tested.

### Data / DR

- Backups and PITR are enabled where required.
- Restore has been tested in an isolated environment.
- RTO/RPO are stated per data class.
- Data corruption recovery is considered separately from HA.

### Security / Access

- Security design review is complete for exposed paths.
- Privileged access is least-privilege and auditable.
- Secrets are stored in approved systems.
- Logs do not leak sensitive data.

## Output Template

```markdown
## Readiness Decision
- Ready / Conditional / Blocked:
- Reason:
- Decision owner:

## SLO / Launch Risk
- Protected journey:
- SLI:
- SLO:
- Error budget policy:

## Blockers
| Priority | Area | Blocker | Risk | Required fix | Owner |
|---|---|---|---|---|---|

## Conditional Launch Controls
- Canary:
- Rollback:
- Kill switch:
- Monitoring:
- Staffing:

## Follow-up
1. [Owner] [Action] [Deadline]
```
