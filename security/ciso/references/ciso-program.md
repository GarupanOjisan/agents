# CISO Program Reference

Source references:
- NIST Cybersecurity Framework 2.0: https://www.nist.gov/cyberframework
- CIS Critical Security Controls: https://www.cisecurity.org/controls
- OWASP Top Ten: https://owasp.org/www-project-top-ten/
- MITRE ATT&CK: https://attack.mitre.org/

## Operating Model

A practical CISO program connects business risk to security control execution. Keep these artifacts current:

- Asset inventory with owner, criticality, data classification, and exposure.
- Risk register with likelihood, impact, mitigation, owner, due date, and residual risk.
- Control catalog mapped to frameworks where needed.
- Security roadmap split by quarter and risk reduction target.
- Incident response plan with legal, comms, executive, and engineering contacts.
- Exception register with expiration dates and compensating controls.

## Risk Scoring

Use simple scoring unless the organization already has a formal model.

```text
Risk = Threat likelihood x Exposure x Business impact x Control weakness
```

Score each 1-5 and record evidence. The score is a prioritization tool, not a substitute for judgment.

## Control Categories

| Category | Examples | Evidence |
|---|---|---|
| Identity | SSO, MFA, least privilege, break-glass | IAM exports, access reviews |
| Device | MDM, EDR, patch compliance | Device posture dashboards |
| Application | SAST, DAST, dependency scan, code review | CI logs, findings SLA |
| Cloud | Org Policy, SCC, VPC SC, logging | Policy exports, SCC findings |
| Data | classification, encryption, DLP, retention | KMS policy, DLP reports |
| Detection | SIEM rules, alert SLAs, ATT&CK coverage | rule repo, cases |
| Response | tabletop, runbooks, postmortems | exercise records |
| Third party | vendor review, DPA, security questionnaires | vendor files |

## Metrics

Use metrics that drive action:

- Critical vulnerability SLA compliance.
- Percent of production services with owner, SLO, threat model, and runbook.
- MFA/SSO coverage for privileged users.
- External attack surface count and stale asset count.
- MTTD / MTTC / MTTR for confirmed incidents.
- High severity SCC findings open past SLA.
- Detection coverage for ATT&CK techniques relevant to the business.
- Security exception count and age.

## Board / Executive Summary Shape

```markdown
## Security Posture
[Green/Yellow/Red with one-sentence rationale]

## Material Risks
1. [Risk] - [Business impact] - [Decision needed]

## Progress
- [Completed risk reduction]
- [Metric movement]

## Decisions / Investment
- [Decision, cost, expected risk reduction]
```
