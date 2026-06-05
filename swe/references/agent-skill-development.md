# Agent Skill / Harness Development

Source references:
- Anthropic public Agent Skills repository: https://github.com/anthropics/skills
- Anthropic Claude Code skill-development guidance: https://github.com/anthropics/claude-code
- Google public Agent Skills repository: https://github.com/google/skills

## Skill Shape

Use this structure:

```text
skill-name/
├── SKILL.md
├── references/
├── scripts/
└── examples/
```

`SKILL.md` must include YAML frontmatter:

```yaml
---
name: skill-name
description: Strong trigger description with specific use cases.
---
```

## Progressive Disclosure

- Keep `SKILL.md` focused on role, trigger routing, workflow, boundaries, and output templates.
- Move long procedures, product-specific details, and reference tables to `references/`.
- Use `scripts/` for deterministic repetitive work.
- Use `examples/` for copyable patterns.

## Description Quality

The description is the primary trigger. Include:

- The domain.
- The concrete tasks.
- Important trigger keywords.
- When to use the skill even if the user does not name it.
- Adjacent skills to combine with when relevant.

## Third-party Skill Intake

Before incorporating public skills:

1. Confirm source reputation and license.
2. Read the skill body and any referenced scripts.
3. Avoid blindly importing executable scripts.
4. Summarize or adapt the parts that fit local workflows.
5. Record source URLs in the reference file.
6. Test that `install.sh --list` discovers the skill.

## Validation Checklist

- `SKILL.md` has `name` and `description`.
- Names are unique across the repo.
- Referenced files exist.
- The skill has clear boundaries and escalation paths.
- Output templates match the work the user usually needs.
- `./install.sh --list` succeeds.
