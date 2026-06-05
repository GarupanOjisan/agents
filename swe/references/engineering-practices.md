# Engineering Practices

## Read Before Editing

- Inspect file layout and nearby patterns.
- Check tests and fixtures before inventing new ones.
- Check git status and avoid reverting unrelated changes.
- Prefer `rg` / `rg --files` for discovery.

## Design Rules

- Keep changes close to the requested behavior.
- Use existing framework utilities before adding libraries.
- Favor clear data structures over string parsing when a parser/API exists.
- Split files only when it creates a clearer boundary.
- Add comments only for non-obvious reasoning, not line-by-line narration.

## Error Handling

- Make failure mode explicit: validation error, retryable external error, permanent external error, internal bug.
- Preserve useful context without leaking secrets.
- Avoid swallowing exceptions that change user-visible behavior.
- In user-facing flows, return actionable messages and log detailed diagnostics separately.

## Performance

- Measure before broad optimization.
- Check N+1 queries, repeated network calls, large unbounded lists, blocking commands, and missing indexes.
- Add limits, pagination, deadlines, caching, or batching only where the expected load justifies them.

## Change Summary Template

```markdown
## Changes
- [Concrete change]

## Verification
- [Command] - [Result]

## Risk
- [Remaining risk or "No known residual risk"]
```
