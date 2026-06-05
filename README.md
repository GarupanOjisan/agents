# Agents Harness Repository

普段の業務カテゴリ別に Agent Skills / harness を管理するリポジトリです。

## Categories

| Category | Skill name | Path | Purpose |
|---|---|---|---|
| SRE | `sre` | `sre/` | SLO、インシデント、GCP/GKE/Spanner、Redis Cloud、MySQL、Cloudflare edge、運用改善 |
| SRE | `cloud-troubleshooting` | `sre/cloud-troubleshooting/` | GCP/AWS サービス障害、5xx、レイテンシ、タイムアウト、DNS、IAM/auth、quota、deploy regression の症状別調査 |
| SRE | `redis-ops` | `sre/redis-ops/` | Redis 設計・運用・移行・トラブルシュート |
| SRE | `mysql-ops` | `sre/mysql-ops/` | MySQL / Cloud SQL / RDS / Aurora の運用・性能・バックアップ・障害対応 |
| Security/CISO | `security-ciso` | `security/ciso/` | セキュリティ戦略、統制、クラウドセキュリティ、SOC/IR、経営報告 |
| Security/pentester | `security-pentester` | `security/pentester/` | 許可済み Web/API/cloud pentest、報告、再テスト |
| SWE | `swe` | `swe/` | 設計、実装、レビュー、テスト、Agent Skills / harness 開発 |

## Installation

```bash
./install.sh --list
./install.sh
./install.sh sre cloud-troubleshooting redis-ops mysql-ops security-ciso security-pentester swe
```

`install.sh` は `SKILL.md` を再帰的に探索し、frontmatter の `name` を使って選択したスコープにコピーします。
別リポジトリへ repo scope で入れる場合は `--repo /path/to/repo` を指定します。

### Install Scopes

| Scope | Command | Destination | Intended use |
|---|---|---|---|
| User/global | `./install.sh --scope user` | `~/.claude/skills/` | 自分の全リポジトリで使う個人スキル |
| Repository/team-shared | `./install.sh --scope repo-team` | `.claude/skills/` | リポジトリにコミットしてチームで共有するスキル |
| Repository/user-only | `./install.sh --scope repo-user` | `.claude/skills/` + `.git/info/exclude` | このリポジトリだけで個人利用し、コミットしないスキル |

Examples:

```bash
# Global install. This is the default.
./install.sh --scope user sre cloud-troubleshooting mysql-ops

# Team-shared project install. Commit .claude/skills after reviewing the diff.
./install.sh --scope repo-team sre security-ciso

# Local-only project install. The installed skill path is added to .git/info/exclude.
./install.sh --scope repo-user swe

# Install from this harness repo into another repository.
./install.sh --scope repo-user --repo /path/to/repo sre cloud-troubleshooting mysql-ops

# List or uninstall in a specific scope.
./install.sh --scope repo-team --list
./install.sh --scope user --uninstall sre
```

### Bulk Updates

複数リポジトリに散らばった repo-local harness は `sync-installs.sh` で一括更新できます。

```bash
cp install-targets.example.tsv install-targets.tsv
$EDITOR install-targets.tsv
./sync-installs.sh install-targets.tsv
```

`install-targets.tsv` の形式:

```text
scope repo-path-or-- skill [skill ...]
```

例:

```text
user - swe
repo-user /Users/m0tch/dev/SingColor/singcolor-server sre cloud-troubleshooting mysql-ops redis-ops
repo-user /Users/m0tch/dev/security-work security-ciso security-pentester
```

これで `swe` は global に更新し、業務特化ハーネスは必要なリポジトリだけに更新できます。

## External Sources Incorporated

このリポジトリでは、第三者の公開スキルや資料を丸ごと無検証で取り込まず、業務カテゴリに合う部分を参照資料として要約・適用しています。

| Source | Incorporated into |
|---|---|
| Anthropic public Agent Skills / Claude Code skill-development patterns | `swe/references/agent-skill-development.md`, `swe/references/testing.md` |
| Google public Agent Skills, Google Cloud troubleshooting docs, and Google Cloud Well-Architected Framework | `sre/cloud-troubleshooting/`, `sre/references/google-cloud-waf-reliability.md`, `sre/references/google-cloud-network-observability.md`, `security/ciso/references/cloud-security-governance.md` |
| AWS Well-Architected, CloudWatch, ALB, and operational runbook docs | `sre/cloud-troubleshooting/`, `sre/references/amazon-aws.md` |
| MySQL / Google Cloud SQL / AWS RDS / Aurora official docs | `sre/mysql-ops/` |
| Cloudflare Agents / Workers / Zero Trust / WAF docs | `sre/references/cloudflare-edge-ops.md`, `security/ciso/references/cloud-security-governance.md`, `security/pentester/references/cloud-pentest.md` |
| OWASP / NIST / CIS / MITRE public frameworks | `security/ciso/references/ciso-program.md`, `security/pentester/references/web-api-pentest.md`, existing SOC references |

## Layout

```text
sre/
  SKILL.md
  cloud-troubleshooting/
  references/
  redis-ops/
  mysql-ops/
security/
  ciso/
  pentester/
swe/
  SKILL.md
  references/
```
