# MySQL Replication / Backup / PITR Reference

Source references:
- MySQL 8.4 Reference Manual: https://dev.mysql.com/doc/refman/8.4/en/
- MySQL replication: https://dev.mysql.com/doc/refman/8.4/en/replication.html
- Google Cloud SQL backups: https://cloud.google.com/mysql/cloudsql-setup
- Amazon RDS Multi-AZ: https://aws.amazon.com/rds/details/multi-az/
- Aurora replication: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Replication.html

## Concepts

| Mechanism | Purpose | Not a replacement for |
|---|---|---|
| HA / Multi-AZ | Instance or zone failure recovery | Backup/PITR |
| Read replica | Read scaling or promotion target | Consistent backup |
| Binlog | Replication and point-in-time recovery | Full backup |
| Snapshot/backup | Recovery base image | Low-lag read scaling |
| PITR | Recover before accidental change | HA failover |
| Logical dump | Portability, object-level recovery | Fast large restore |

## Backup Strategy

Define by data class:

- RPO: maximum acceptable data loss.
- RTO: maximum acceptable recovery time.
- Retention: operational mistakes, audit, legal, ransomware.
- Isolation: same project/account, separate project/account, cross-region, immutable/offline.
- Restore validation: scheduled restore to a separate environment.

Minimum production posture:

- Automated backups enabled.
- PITR/binlog retention aligned to incident discovery time.
- Restore drill performed before depending on the plan.
- Backups protected from the same IAM principal that can damage production.
- Runbook includes restore, validation, cutover, and rollback.

## Replication Lag

Causes:

- Large transactions.
- Long-running read queries on replicas.
- Missing indexes on replica-applied writes.
- Replica under-provisioning.
- Network or storage bottlenecks.
- DDL or batch jobs.

Mitigations:

- Route consistency-sensitive reads to primary.
- Split analytical reads away from operational replicas.
- Break large writes into bounded batches.
- Add indexes before high-volume updates.
- Scale replica or reduce replica workload.

## GTID / Binlog

Operational guidance:

- Prefer GTID-based replication for managed cutovers when supported by the platform.
- Keep binlog retention long enough for realistic replica rebuild and PITR windows.
- Confirm row/statement/mixed format implications before relying on logs for recovery or audit.
- Keep runbooks current with MySQL 8.4 terminology and syntax.

## PITR Workflow

1. Identify bad-change timestamp and confidence window.
2. Stop or isolate writers if corruption is ongoing.
3. Restore to a separate instance before the timestamp.
4. Validate row counts, checksums, critical business invariants.
5. Choose recovery path: full cutover, selective logical export/import, or forward repair.
6. Preserve evidence and timeline.

## Migration / Cutover

- Run dual-write only with reconciliation and rollback plan.
- Prefer replication-based migration for large datasets.
- Measure replica lag and write freeze window.
- Validate schema, row counts, checksums, indexes, grants, triggers/events.
- Prepare application endpoint switch and rollback endpoint.
