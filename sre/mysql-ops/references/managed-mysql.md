# Managed MySQL: Cloud SQL / RDS / Aurora

Source references:
- Google Cloud SQL for MySQL high availability: https://docs.cloud.google.com/sql/docs/mysql/high-availability
- Google Cloud SQL for MySQL setup best practices: https://cloud.google.com/mysql/cloudsql-setup
- Amazon RDS Multi-AZ: https://aws.amazon.com/rds/details/multi-az/
- Aurora MySQL HA best practices: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/AuroraMySQL.BestPractices.HA.html
- Aurora replication: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Replication.html

## Decision Matrix

| Platform | HA model | Read scaling | Main operational notes |
|---|---|---|---|
| Cloud SQL for MySQL | Regional instance with primary/standby zones and synchronous persistent disk replication | Separate read replicas | Standby does not serve reads. Failover closes existing connections; applications must reconnect. |
| RDS for MySQL Multi-AZ instance | Primary plus synchronous standby in another AZ | Separate read replicas | Standby is for failover, not read traffic. Backups can be taken from standby. |
| RDS Multi-AZ DB cluster | Writer plus two readable standbys | Reader endpoint | Better failover/read path, different cost and operational profile. |
| Aurora MySQL | Cluster volume across AZs, writer and readers | Reader endpoint / Aurora replicas | Storage layer differs from upstream MySQL/RDS. Failover target choice and reader topology matter. |

## HA Is Not Backup

HA protects against instance or zone failure. It does not protect against:

- Accidental `DELETE` / `UPDATE`.
- Bad migrations.
- Application bugs writing corrupt data.
- Compromised credentials.
- Dropped tables.

Always pair HA with backups, PITR, restore drills, and least-privilege controls.

## Cloud SQL for MySQL

Operational points:

- Use HA/regional instances for production workloads with meaningful availability requirements.
- Cloud SQL failover keeps the same connection string/IP, but active connections are closed and clients must reconnect.
- Place some read replicas outside the primary/standby zones when read availability matters.
- Enable automated backups and PITR for production. The default retention may be too short for business recovery needs.
- Set maintenance windows and test maintenance behavior against connection pools.
- Prefer private IP and controlled egress paths for production services.

Review questions:

- What is the tested RTO/RPO?
- How does the application behave when all connections are dropped for roughly a minute?
- Are read paths safe if replicas lag or disappear?
- Can you restore to a separate instance and validate data before cutover?

## RDS for MySQL

Operational points:

- Multi-AZ instance deployment gives synchronous standby failover, but the standby is not a read target.
- Multi-AZ DB cluster can provide readable standbys and faster failover, with different cost and compatibility considerations.
- Use automated backups and define retention based on business recovery needs.
- RDS Proxy can reduce connection storm impact during failover and deployment spikes.
- Parameter group changes may require restart; classify each change before applying.

Review questions:

- Is the workload on Single-AZ, Multi-AZ instance, Multi-AZ cluster, or Aurora?
- Are application timeouts shorter than failover recovery expectations?
- Does the app use DNS/endpoint behavior correctly after failover?
- Are backups copied cross-region/account when ransomware or account compromise is in scope?

## Aurora MySQL

Operational points:

- Aurora uses a distributed cluster storage model, so storage durability and failover behavior differ from regular RDS MySQL.
- Use at least one appropriately sized reader in another AZ for failover targets.
- Monitor replica lag, commit latency, buffer cache, deadlocks, lock waits, and storage volume growth.
- Reader endpoint is useful for scale, but read-after-write paths must avoid stale reads.
- Aurora Global Database is a DR option when cross-region RTO/RPO requirements justify the complexity and cost.

## Common Anti-patterns

- Treating read replicas as backups.
- Letting connection pools retry indefinitely during failover.
- Sending consistency-sensitive reads to replicas.
- Applying parameter changes without knowing restart requirements.
- Restoring backups only during real incidents.
- Running schema changes without replica-lag and rollback planning.
