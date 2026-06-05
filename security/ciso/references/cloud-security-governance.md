# Cloud Security Governance

Source references:
- Google Cloud Well-Architected Security: https://docs.cloud.google.com/architecture/framework/security
- Google public Agent Skills repository: https://github.com/google/skills
- Cloudflare Zero Trust docs: https://developers.cloudflare.com/cloudflare-one/
- Cloudflare WAF docs: https://developers.cloudflare.com/waf/

## Google Cloud Security Pillars

Use these principles when assessing GCP workloads:

- Security by design: threat model and security requirements are part of initial design.
- Zero trust: continuously verify identity, device, context, and policy.
- Shift-left security: detect security defects in design, code, build, and deploy stages.
- Preemptive cyber defense: use threat intelligence, SCC, and SecOps to reduce dwell time.
- Secure and responsible AI: protect model/data access, tool use, prompts, and outputs.
- AI for security: use automation carefully for triage and remediation.
- Regulatory, compliance, and privacy needs: map controls to obligations and evidence.

## Baseline GCP Controls

- Organization Policy constraints for risky services and public exposure.
- Centralized Cloud Audit Logs with retention and restricted access.
- SCC Premium or equivalent posture monitoring for high-risk environments.
- VPC Service Controls for high-value data boundaries where feasible.
- Workload Identity / least-privilege service accounts.
- KMS key ownership and rotation policy for sensitive systems.
- Artifact scanning, Binary Authorization, and signed images for production deploys.
- Terraform or policy-as-code review for IAM, networking, and storage exposure.

## Cloudflare Governance

- Use Access / Zero Trust for admin paths and internal tools.
- Protect origins from direct access when Cloudflare is the intended enforcement layer.
- Maintain WAF, rate limiting, bot, and DDoS policy baselines.
- Review Workers routes and transform rules as code where possible.
- Log WAF and Access events into the central detection pipeline.

## Tier-0 / Recovery Infrastructure

Treat the following as Tier-0 or recovery-critical control planes:

- Identity provider, SSO, MFA, password reset, and help desk identity-proofing workflows.
- Backup control planes, backup service accounts, immutable storage, and restore credentials.
- Hypervisors, virtualization management planes, Kubernetes control planes, and EDR admin consoles.
- CI/CD systems, artifact registries, secret managers, and infrastructure-as-code pipelines.
- Cloud organization/folder/project admin roles and break-glass accounts.

Controls:

- Separate administrative identities from daily-use identities.
- Decouple backup administration from the primary corporate domain where practical.
- Use immutable or object-lock storage for recovery-critical backups.
- Test restore paths from credentials and infrastructure that survive domain compromise.
- Require stronger approval and monitoring for deletion of backups, identity policies, hypervisor resources, and logging sinks.
- Monitor Tier-0 administrative actions with long retention and high-priority alerting.

## SaaS Identity / Token Governance

Modern intrusions often bypass classic endpoint controls through SaaS and identity systems.

- Inventory OAuth apps, service principals, API tokens, personal access tokens, SCIM integrations, and marketplace apps.
- Enforce least privilege, short token lifetime where possible, and periodic access review.
- Route SaaS access through the central IdP and disable unmanaged local accounts.
- Harden help desk workflows against vishing and MFA reset abuse.
- Alert on suspicious OAuth consent, impossible travel, mass export, unusual API volume, token creation, and new admin grants.
- Keep SaaS admin, audit, and API activity logs in centralized long-term storage.

## Edge Device Visibility

VPNs, routers, firewalls, load balancers, and other edge/core devices often lack EDR coverage.

- Forward administrative logs, configuration changes, authentication events, VPN session logs, and application logs centrally.
- Track firmware/software versions and known exploited vulnerabilities.
- Monitor unexpected packet capture use, new local users, config export, tunnel changes, and unexplained reboots.
- Keep golden configuration snapshots and verify drift.
- Define containment and rebuild procedures before compromise.

## AI / Agent Security

- Inventory AI tools, model providers, data classes, and connected tools.
- Restrict tool permissions to the minimum needed for the workflow.
- Treat third-party skills, plugins, and MCP servers as executable supply chain components.
- Review prompts or instructions that can trigger data exfiltration, unsafe tool use, or policy bypass.
- Log agent actions where they touch code, infrastructure, customer data, or security controls.

## Review Output

```markdown
## Cloud Security Assessment
| Area | Status | Evidence | Gap | Recommendation |
|---|---|---|---|---|

## Priority Fixes
1. [Highest risk fix]
2. [Second fix]
3. [Third fix]

## Residual Risk
[What remains after recommended mitigations]
```
