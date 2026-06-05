# Code Review Reference

## Review Posture

Prioritize bugs, regressions, data loss, security issues, reliability problems, and missing tests. Style comments are useful only when they hide a real maintenance risk.

## Severity

| Priority | Meaning |
|---|---|
| P0 | Breaks production, corrupts data, critical security issue |
| P1 | Likely user-visible bug, serious regression, high security/reliability risk |
| P2 | Edge-case bug, maintainability issue with likely future cost, missing important test |
| P3 | Minor improvement, clarity, non-blocking polish |

## Required Output Shape

```markdown
## Findings
- [P1] [Title] - path/to/file.ext:123
  [Why this is wrong, how it manifests, and what to change]

## Open Questions
- [Only if needed]

## Summary
[Brief secondary context]

## Test Gaps
- [Missing verification]
```

If there are no findings, say that clearly and mention residual risk or unrun tests.

## Review Checklist

- Does the code preserve existing API contracts?
- Are authz/authn checks enforced server-side?
- Are external calls bounded by timeouts/retries?
- Is input validation in the right layer?
- Can errors leak secrets or hide actionable failures?
- Are migrations, rollbacks, and data compatibility handled?
- Do tests cover the changed behavior and failure mode?
