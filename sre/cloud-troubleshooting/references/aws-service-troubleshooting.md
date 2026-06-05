# AWS Service Troubleshooting

Source references:
- AWS Well-Architected Operational Excellence, Operate: https://docs.aws.amazon.com/wellarchitected/latest/operational-excellence-pillar/operate.html
- Application Load Balancer monitoring: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-monitoring.html
- Application Load Balancer CloudWatch metrics: https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-cloudwatch-metrics.html
- AWS Cloud Operations runbooks/playbooks blog: https://aws.amazon.com/blogs/mt/achieving-operational-excellence-using-automated-playbook-and-runbook/

Use this for AWS services where the symptom is service-level 5xx, latency, timeout, DNS, auth/IAM, quota, deploy regression, or dependency degradation.

## Evidence Sources

| Layer | Primary evidence |
|---|---|
| Route 53 / DNS | resolver result, health checks, record changes, TTL, failover policy |
| CloudFront / API Gateway / ALB/NLB | CloudWatch metrics, access logs, target health, response code split, target response time |
| ECS / EKS | task/pod restarts, deployment events, CPU/memory, target registration, readiness, scaling events |
| Lambda | errors, duration, throttles, concurrency, cold start indicators, DLQ/on-failure destinations |
| RDS / Aurora | connections, CPU, I/O, locks, slow queries, replica lag, failover events; then load `mysql-ops` for MySQL |
| ElastiCache / Redis | engine CPU, memory, evictions, latency, connections, failover events; then load `redis-ops` |
| IAM/auth | CloudTrail, IAM policy changes, STS errors, KMS grants, secret rotation |
| Network | VPC Flow Logs, security groups, NACLs, NAT Gateway metrics, route tables, PrivateLink |
| Quota/capacity | Service Quotas, throttling metrics, autoscaling activity, account/region limits |

## AWS Initial Flow

1. Identify the entry point: Route 53, CloudFront, API Gateway, ALB/NLB, private service, or queue.
2. Split edge-generated errors from target-generated errors using ALB/API Gateway/CloudFront metrics and logs.
3. Compare affected dimensions: region, AZ, target group, service version, task set, deployment, tenant, endpoint.
4. Check deployment and autoscaling events before low-level infrastructure debugging.
5. Check saturation: target response time, CPU/memory, container restarts, Lambda throttles, queue age, connection pools.
6. Check dependencies: RDS/Aurora, ElastiCache, DynamoDB, SQS/SNS, external services, identity/KMS.
7. Check CloudTrail for config/IAM/security group/target group changes in the incident window.

## Symptom Playbooks

### 5xx

- Split `HTTPCode_ELB_5XX` from `HTTPCode_Target_5XX` for ALB.
- If LB-generated 5xx rises without target logs, inspect target health, deregistration, security groups, listener rules, idle timeout, and connection errors.
- If target-generated 5xx rises, inspect application logs, deployment diff, dependency spans, and saturation.
- Mitigate with rollback, target group traffic shift, disabling a feature, scaling targets, or routing away from unhealthy AZ/cell.

### Latency

- Compare ALB target response time, application duration, dependency latency, and queue age.
- Check p95/p99 and per-AZ/per-target group skew.
- For ECS/EKS, check CPU throttling, memory pressure, task restarts, readiness, target registration churn, and autoscaling lag.
- For Lambda, check duration, concurrent executions, throttles, provisioned concurrency, and downstream latency.
- Mitigate with scale-out, concurrency limits, load shedding, circuit breakers, or rollback.

### Timeout

- Identify whether timeout occurs at client, CloudFront/API Gateway/ALB, service runtime, HTTP client, DB/cache, or third party.
- Check idle timeout, target response time, connection reuse, NAT Gateway metrics, DNS resolution, and security group/NACL changes.
- Mitigate by rollback, dependency isolation, traffic shift, capacity action, or temporary timeout adjustment if it does not hide data loss.

### DNS / Routing

- Check Route 53 record set changes, health checks, resolver behavior, TTL, weighted/failover policies, and CloudFront origin config.
- Compare public and VPC resolver answers when internal services are involved.
- Mitigate by reverting record changes, failing over to known-good endpoint, or adjusting weights.

### IAM / Auth / KMS

- Check CloudTrail for IAM policy, role trust, KMS key policy, secret rotation, and security group changes.
- Compare failing principal/action/resource with last-known-good.
- Mitigate by reverting the exact change or restoring a known-good role/policy with security review.

### Quota / Capacity

- Check throttling metrics, Service Quotas, autoscaling activity, and regional/AZ headroom.
- Validate failover target capacity before shifting traffic.
- Mitigate with quota increase, warm capacity, traffic shed, or feature degradation.

## AWS Output Additions

```markdown
## AWS Evidence
- Account / region / service:
- Entry point:
- Deployment / task set / version:
- Edge or LB signal:
- Runtime signal:
- Dependency signal:
- CloudTrail/config changes:
- Quota / capacity:
```
