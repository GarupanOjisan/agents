# Toil / On-call Health

Source references:
- Google SRE Eliminating Toil: https://sre.google/sre-book/eliminating-toil/
- Google SRE Workbook Eliminating Toil: https://sre.google/workbook/eliminating-toil/

Use this reference for alert fatigue, on-call health, operational load, runbook automation, toil reduction, and SRE staffing discussions.

## Principle

Google SRE aims to keep operational work below 50% of SRE time so at least 50% remains for engineering work that reduces future toil or improves reliability, performance, or utilization.

## Toil Definition

Toil is work that tends to be:

- Manual.
- Repetitive.
- Automatable.
- Tactical rather than strategic.
- No enduring value.
- Scales linearly with service growth.

Not all operational work is toil. Incident command, postmortems, and one-off debugging can be valuable operational work. Repeated manual remediation is toil.

## On-call Health Metrics

Track:

- Toil ratio: operational/toil time vs engineering time.
- Page volume per shift.
- Off-hours pages.
- TTA: time to acknowledge.
- TTM: time to mitigate.
- TTR: time to recover.
- Alert actionability: percent of pages that required immediate human action.
- Noisy alert count and top alert sources.
- Runbook coverage and runbook success rate.
- Repeated manual task count.

## Review Checklist

- Are pages tied to user-visible symptoms or urgent risk?
- Does every page have a clear action and owner?
- Are low-priority alerts routed to ticket or dashboard instead of page?
- Are repeated manual fixes being converted into automation?
- Are runbooks executable by an on-call engineer under stress?
- Are postmortem actions reducing future pages?
- Is on-call load sustainable across the rotation?

## Output Template

```markdown
## On-call Health
- Toil ratio:
- Page volume:
- Off-hours pages:
- TTA / TTM / TTR:
- Actionable page rate:

## Top Toil Sources
| Rank | Source | Frequency | Manual time | Automation candidate |
|---|---|---:|---:|---|

## Alert Quality
- Page-worthy:
- Ticket-worthy:
- Delete / dashboard-only:

## Improvement Backlog
| Priority | Fix | Expected reduction | Owner | Deadline |
|---|---|---|---|---|
```
