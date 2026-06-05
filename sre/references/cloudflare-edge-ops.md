# Cloudflare Edge / Agents Operations

Source references:
- Cloudflare Agents repository: https://github.com/cloudflare/agents
- Cloudflare Workers docs: https://developers.cloudflare.com/workers/
- Cloudflare Zero Trust docs: https://developers.cloudflare.com/cloudflare-one/
- Cloudflare WAF docs: https://developers.cloudflare.com/waf/

Use this reference when a workload uses Cloudflare Workers, Pages, Durable Objects, Agents, KV, R2, D1, CDN, WAF, or Zero Trust.

## Operating Model

Cloudflare edge services often shift failure modes from instance health to global routing, cache behavior, durable object placement, data consistency, and policy configuration. Review them as distributed systems, not as a static CDN layer.

## Reliability Checklist

- Define which responses are cacheable and which must be origin-fresh.
- Document cache keys, purge strategy, and stale-while-revalidate behavior.
- Validate origin failover and fallback behavior.
- For Durable Objects / Agents, identify state ownership, migration path, hibernation behavior, and reconnect behavior.
- Bound CPU time, subrequest count, payload size, and external dependency calls.
- Use idempotency keys for retries from Workers to origins or APIs.
- Keep deploy rollback simple: versioned Workers, traffic split, and known-good route mapping.

## Security Checklist

- Use WAF rules and rate limits for commodity attacks before application code.
- Require mTLS, Access, or signed requests for administrative or origin-only paths.
- Protect origin bypass: restrict direct origin access where practical.
- Keep secrets in platform secret storage, not in code or wrangler config committed to git.
- Review transform rules, redirects, and worker routes for unintended exposure.
- Log security-relevant requests with privacy-aware sampling.

## Observability Checklist

- Capture request ID, colo, route, worker version, cache status, origin status, and user-impact label.
- Separate edge errors from origin errors.
- Track p50/p95/p99 latency at edge and origin.
- Monitor WAF/rate-limit actions and false positive reports.
- Keep runbooks for cache purge, route rollback, origin isolation, and Access policy rollback.

## Review Prompts

- What happens if the origin is slow but not down?
- What happens if a purge fails or is delayed?
- Can a user bypass Cloudflare and hit the origin directly?
- Which user-visible SLO is served by the edge layer?
- Which edge configuration change is most dangerous and how is it reviewed?
