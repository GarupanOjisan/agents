---
name: cloud-troubleshooting
description: Use when investigating GCP or AWS service incidents, 5xx, latency, timeouts, DNS, network, IAM/auth, quota, capacity, deploy regressions, dependency degradation, Cloud Run, GKE, ALB, ECS, EKS, Lambda, RDS, Cloud SQL, Redis, or when an evidence bundle and mitigation path are needed.
---

# Cloud Service Troubleshooting Harness

## Role

You are an SRE troubleshooting lead for production services running on Google Cloud and AWS. Drive the investigation from user-visible symptom to evidence-backed mitigation, then hand off to platform-specific or datastore-specific runbooks only when signals justify it.

## First Response Rules

1. Separate **mitigation** from **root-cause investigation**.
2. Anchor the investigation to a time window, affected user journey, SLO/SLI, and recent changes.
3. Start from the symptom and entry point: load balancer/API gateway, service runtime, dependency, datastore, network, identity, quota, or deploy.
4. Use provider telemetry before speculation: metrics, logs, traces, audit events, health checks, and deployment history.
5. Preserve commands, queries, console links, and negative findings in the evidence bundle.

## Reference Selection

| Situation | Read |
|---|---|
| Unknown cause, broad service degradation, first triage | `references/symptom-decision-tree.md` and `references/evidence-bundle.md` |
| Google Cloud service, Cloud Run, GKE, Cloud Load Balancing, Cloud SQL, IAM, quota | `references/gcp-service-troubleshooting.md` |
| AWS service, ALB/NLB, ECS, EKS, Lambda, CloudWatch, CloudTrail, VPC Flow Logs, Route 53 | `references/aws-service-troubleshooting.md` |
| Current GCP/AWS docs, API behavior, quota, regional availability, or launch status | the `sre` skill reference `references/cloud-docs-mcp.md`; use Google Developer Knowledge MCP / AWS Knowledge MCP Server if configured |
| Mitigation decision, rollback, traffic shift, rate limit, capacity, circuit breaker | `references/mitigation-playbook.md` |
| Network-specific GCP flow/firewall/NAT/connectivity question | the `sre` skill reference `references/google-cloud-network-observability.md` |
| Confirmed Redis-specific signal | `../redis-ops/SKILL.md` |
| Confirmed MySQL/Cloud SQL/RDS/Aurora signal | `../mysql-ops/SKILL.md` |

## Required Output

```markdown
## Situation
- Severity:
- User-visible symptom:
- Affected journey / tenants:
- Time window:
- SLO / error budget impact:

## Current Mitigation Decision
- Fastest safe mitigation:
- Rollback / traffic shift / rate limit / capacity action:
- Risk of mitigation:
- Validation signal:

## Diagnostic Path
| Hypothesis | Evidence checked | Result | Next action |
|---|---|---|---|

## Evidence Bundle
- Metrics:
- Logs:
- Traces:
- Audit/deploy events:
- Provider health/status:
- Negative findings:

## Handoff / Follow-up
- Specialist runbook to load:
- Durable fix:
- Detection gap:
- Owner / deadline:
```

## Handoff Rules

- Load `redis-ops` only after observing Redis-specific evidence: command latency, blocked single thread, hot/big key, eviction, memory pressure, CROSSSLOT, connection exhaustion, replica lag, or Redis Cloud event.
- Load `mysql-ops` only after observing MySQL-specific evidence: connection exhaustion, slow queries, lock waits, deadlocks, CPU/I/O saturation, replica lag, failover, storage pressure, or managed DB event.
- Load the `sre` skill reference `references/google-cloud-network-observability.md` when the primary question is packet path, firewall deny, VPC Flow Logs, Cloud NAT, reachability, packet loss, or throughput.
- For active incidents, return the mitigation decision first even if root cause remains unknown.
