# MySQL Performance / Query / DDL Reference

Source references:
- MySQL 8.4 Reference Manual: https://dev.mysql.com/doc/refman/8.4/en/
- MySQL Slow Query Log: https://dev.mysql.com/doc/refman/8.4/en/slow-query-log.html

## First Principles

- Diagnose from evidence: query latency, rows examined, lock waits, I/O, CPU, memory, connection usage, and replication lag.
- Optimize the query and access path before scaling vertically.
- Avoid production-wide introspection queries without limits.
- Treat DDL as a production change with latency, lock, replication, and rollback risk.

## Triage Metrics

| Symptom | Check |
|---|---|
| High latency | slow query log, Performance Schema, p95/p99, rows examined |
| CPU high | top statements, full scans, sort/temp tables, JSON/functions |
| I/O high | buffer pool hit ratio, dirty pages, redo/binlog fsync, table scans |
| Writes slow | lock waits, fsync, secondary index count, hot rows |
| Connection errors | max connections, pool size, thread usage, proxy/RDS Proxy |
| Read replica stale | replication lag, long queries, large transactions |

## Slow Query Workflow

1. Confirm time window and user-facing impact.
2. Identify top queries by total time, p95/p99 latency, rows examined, and frequency.
3. Run `EXPLAIN` or `EXPLAIN ANALYZE` on representative queries in a safe environment.
4. Compare predicates and ordering with available indexes.
5. Check whether the query changed, data volume changed, stats changed, or plan changed.
6. Apply the smallest safe fix: index, query rewrite, pagination, limit, batching, cache, or workload isolation.

## Index Review

Checklist:

- Equality columns before range columns in composite indexes.
- Index supports `WHERE`, `JOIN`, `ORDER BY`, and `LIMIT` together where needed.
- Cardinality is high enough to justify the index.
- Added index write amplification is acceptable.
- Redundant/duplicate indexes are removed only after confirming usage.
- Large index builds are planned as online DDL or external migration tooling.

## Locking / Deadlocks

Common causes:

- Updating rows in inconsistent order.
- Range predicates that take next-key/gap locks.
- Long transactions holding locks while doing external work.
- Missing indexes causing broad scans under write statements.
- Batch jobs touching hot rows.

Operational rules:

- Keep transactions short.
- Do not call external APIs while holding DB transactions.
- Update hot entities in deterministic order.
- Make deadlock retry safe and idempotent.
- Log enough context to identify conflicting code paths.

## Online DDL

Before DDL:

- Estimate table size and write rate.
- Confirm native online DDL algorithm/lock behavior for the exact operation and version.
- Check replica lag tolerance.
- Prepare rollback or forward-fix plan.
- Test on production-like data.

Tools:

- Native MySQL online DDL when operation is supported and impact is acceptable.
- `pt-online-schema-change` for controlled copy/swap workflows.
- `gh-ost` for binlog-driven online migrations.
- Managed service migration tools when platform restrictions apply.

## Query Output Template

```markdown
## Query Diagnosis
- Query fingerprint:
- Time window:
- Total time / p95 / count:
- Plan:
- Bottleneck:

## Recommendation
- Change:
- Expected effect:
- Write/DDL risk:
- Verification:
```
