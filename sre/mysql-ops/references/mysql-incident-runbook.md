# MySQL Incident Runbook

## Initial Triage

Collect:

- User impact: read failures, write failures, latency, stale data, partial feature impact.
- Platform: self-managed, Cloud SQL, RDS MySQL, Aurora MySQL.
- Top symptom: CPU, I/O, locks, connections, replica lag, storage, failover, errors.
- Recent changes: deploys, migrations, batch jobs, traffic spike, parameter changes, failover, maintenance.
- Data safety: suspected corruption, accidental writes, dropped tables, security incident.

If the starting point is a broad GCP/AWS service symptom rather than a confirmed database symptom, begin with the `cloud-troubleshooting` skill. Enter this runbook after evidence points to MySQL: connection exhaustion, slow queries, lock waits, deadlocks, CPU/I/O saturation, replica lag, failover, storage pressure, or managed DB events.

## Cloud Service Handoff Signals

Use this runbook when the cloud troubleshooting evidence shows:

- Application connection pool saturation aligned with DB connection count.
- Load balancer or runtime latency dominated by DB spans.
- Cloud SQL/RDS/Aurora CPU, I/O, storage, or replica lag spike.
- MySQL error codes in app logs such as connection failures, lock wait timeout, deadlock, or read-only after failover.
- Managed database maintenance, restart, failover, backup, or storage event in the incident window.
- Slow query sample or lock graph tied to the affected user journey.

## Mitigation Priority

1. Protect data from further damage.
2. Restore write path if safe.
3. Reduce load: disable expensive feature, stop batch, rate limit, route reads, increase capacity.
4. Preserve evidence: logs, slow query samples, metrics, timeline.
5. Implement durable fix after mitigation.

## Connection Exhaustion

Symptoms:

- `Too many connections`
- App timeouts during deploy or failover
- High active connection count

Actions:

- Confirm app pool size multiplied by replica count and instance count.
- Kill only clearly safe idle or runaway sessions.
- Reduce rollout concurrency.
- Add or tune proxy layer: Cloud SQL connector/proxy, RDS Proxy, ProxySQL where appropriate.
- Set sane connection lifetime and retry backoff.

## Lock Waits / Deadlocks

Actions:

- Identify blocking transaction and statement.
- Check transaction age and source application.
- Stop the offending batch/job if user impact is high.
- Avoid broad `KILL` without understanding rollback cost.
- Add deadlock-safe retry to application path if missing.

Useful SQL, scope carefully:

```sql
SHOW PROCESSLIST;
SHOW ENGINE INNODB STATUS;
```

## Replica Lag

Actions:

- Confirm whether stale reads affect user flows.
- Temporarily route critical reads to primary.
- Stop heavy replica queries.
- Check large transactions or DDL on primary.
- Scale replica if under-provisioned.

## Storage Full

Actions:

- Stop write-heavy batch jobs.
- Confirm auto storage increase setting if managed.
- Identify largest tables/indexes.
- Avoid emergency deletes without binlog/replication impact review.
- Prefer adding storage first, then cleanup.

## Failover

Actions:

- Expect active connections to drop.
- Verify application reconnect and pool behavior.
- Confirm writer endpoint and primary role.
- Check replica lag after promotion.
- Validate writes and critical transactions.

## Accidental Data Change

Actions:

- Stop writers or isolate affected feature.
- Identify exact timestamp and SQL/change source.
- Restore to separate instance using PITR.
- Validate before copying data back or cutting over.
- Preserve audit logs and root-cause timeline.

## Incident Output Template

```markdown
## Impact
- User impact:
- Start time:
- Affected DB:

## Current State
- Writes:
- Reads:
- Lag:
- Errors:

## Mitigation
1. [Action]

## Evidence
- Metrics:
- Logs:
- SQL:

## Follow-up
- Prevent:
- Detect:
- Recover:
```
