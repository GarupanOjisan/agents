# Cloud Official Documentation MCP

Use these MCP servers when the answer depends on current Google Cloud or AWS documentation, product behavior, API parameters, quotas, regional availability, troubleshooting guidance, or newly released features.

## Servers

| Provider | Claude Code server name | URL | Authentication |
|---|---|---|---|
| Google Developer Knowledge MCP | `google-dev-knowledge` | `https://developerknowledge.googleapis.com/mcp` | Google Developer Knowledge API key for the Claude Code setup used here |
| AWS Knowledge MCP Server | `aws-knowledge-mcp-server` | `https://knowledge-mcp.global.api.aws` | None required; public internet access and rate limits apply |

## Official Sources

- Google Developer Knowledge MCP: https://developers.google.com/knowledge/mcp
- AWS Knowledge MCP Server announcement: https://aws.amazon.com/about-aws/whats-new/2025/10/aws-knowledge-mcp-server-generally-available/
- AWS Knowledge MCP Server docs: https://awslabs.github.io/mcp/servers/aws-knowledge-mcp-server

## Install For Claude Code

Default to local scope in the target repository so unrelated repositories do not pay context/tooling cost.

```bash
GOOGLE_DEVELOPER_KNOWLEDGE_API_KEY=... ./install-cloud-docs-mcp.sh --repo /path/to/repo
```

AWS only:

```bash
./install-cloud-docs-mcp.sh --repo /path/to/repo --skip-google
```

User/global scope, only when you intentionally want these docs tools everywhere:

```bash
GOOGLE_DEVELOPER_KNOWLEDGE_API_KEY=... ./install-cloud-docs-mcp.sh --scope user
```

## When To Use

Use Google MCP for:

- Google Cloud service limits, API behavior, setup steps, Cloud Run, GKE, Cloud SQL, Spanner, Cloud Load Balancing, Cloud Monitoring, IAM, and troubleshooting.
- Questions where the static harness may be stale.
- Official examples or code snippets.

Use AWS MCP for:

- AWS service APIs, best practices, What's New, Well-Architected, CloudFormation/CDK, regional availability, troubleshooting, and AWS agent skills.
- Region-specific availability or feature rollout checks.
- Current AWS release and service behavior questions.

## Operating Rules

- Prefer MCP-backed official documentation for facts that can change: quotas, limits, regional availability, API parameters, pricing, service support, and launch status.
- Cite the retrieved official page or tool result in the answer.
- If the MCP server is unavailable, say so and fall back to the static reference plus explicit uncertainty.
- Never place API keys in repo files, `.mcp.json`, committed manifests, or skill references.
