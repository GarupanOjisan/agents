# Google Cloud Network Observability

Source references:
- Google public Agent Skills repository: https://github.com/google/skills
- Google Cloud Network Intelligence Center / Flow Analyzer: https://console.cloud.google.com/net-intelligence/flow-analyzer

Use this reference for VPC Flow Logs, firewall logs, threat logs, Cloud NAT logs, packet loss, throughput, latency, and Connectivity Tests.
For broad Google Cloud service troubleshooting such as 5xx, runtime latency, timeout, IAM/auth, quota, deploy regression, Cloud Run, GKE, or Cloud SQL symptoms, start with the `cloud-troubleshooting` skill. Use this file when the investigation has become network-specific.

## Investigation Principles

- Answer the direct question first. Do not expand scope after a conclusive result unless the user asks.
- Choose the primary data source before querying.
- For high-volume log analysis, prefer BigQuery-linked logging datasets over Cloud Logging UI/API.
- Treat `0`, no records, or no traffic as a valid finding for the requested time range.
- Print SQL or CLI commands before running them when the command could be expensive or broad.

## Data Source Selection

| Need | Primary source | Notes |
|---|---|---|
| Top talkers / bytes / flows | BigQuery exported VPC Flow Logs | Aggregate in SQL |
| Blocked traffic | Firewall Logs | Filter DENY rules and target tags |
| Egress/NAT issues | Cloud NAT logs and NAT metrics | Check port exhaustion |
| Path reachability | Connectivity Tests | Static reachability, route, firewall diagnosis |
| Malware/IPS signals | Cloud IDS / Firewall Plus threat logs | Map to asset and policy |
| Latency/packet loss | Network metrics | Avoid manual point aggregation |

## Handoff From Service Troubleshooting

Load this reference when the cloud service investigation finds one of these signals:

- Load balancer 5xx without backend application logs.
- Backend health check failures or probe timeouts.
- Cloud NAT port exhaustion, egress reset, or connection timeout.
- Firewall deny, missing route, asymmetric path, or VPC Service Controls network boundary issue.
- Per-zone or per-subnet packet loss/throughput skew.
- Connectivity Tests needed to prove static reachability.

## Query Recovery

If a BigQuery query fails with field errors:

1. Run `bq show --schema --format=json PROJECT:DATASET.TABLE`.
2. Confirm whether the schema uses `jsonPayload`, `json_payload`, or exported nested records.
3. Dry-run the corrected SQL with `bq query --use_legacy_sql=false --dry_run`.
4. Retry once with the corrected field names.

## Output Template

```markdown
## Finding
[Direct answer with time range and data source]

## Evidence
- Query/command:
- Result:
- Console link:

## Interpretation
[What this means and what it does not prove]

## Next Action
[One or two concrete next steps only]
```
