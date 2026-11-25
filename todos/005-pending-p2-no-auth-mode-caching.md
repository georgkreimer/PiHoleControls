---
status: pending
priority: p2
issue_id: "005"
tags: [code-review, performance]
dependencies: ["001"]
---

# No Caching of Successful Auth Mode / API Version

## Problem Statement

`PiHoleClient` is created as an ephemeral struct for each operation and cannot cache which auth mode or API version succeeded. Every poll cycle (20s) tries all auth modes from scratch. A single operation can fire up to 12+ HTTP requests (3 endpoints x 4 auth modes) before falling back to v5, which adds another request.

**Why it matters:** On misconfigured setups or v5 servers, every 20-second poll exhausts all possibilities. On low-power Pi-hole hardware, this creates unnecessary load and log noise.

## Findings

- **Identified by:** Performance Oracle
- **Steady state (well-configured v6):** 1-2 requests per poll -- acceptable
- **Worst case (misconfigured/v5):** 5-13 requests per poll cycle

## Proposed Solutions

### Option A: Cache successful auth mode and API version in PiHoleStore
- **Pros:** Eliminates wasted requests; store already manages client lifecycle
- **Cons:** Needs invalidation on settings change
- **Effort:** Medium
- **Risk:** Low

### Option B: Cache in a static/actor similar to PiHoleSessionCache
- **Pros:** Self-contained; works with ephemeral client structs
- **Cons:** Another singleton to manage
- **Effort:** Medium
- **Risk:** Low

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] After first successful request, subsequent polls use the known-working auth mode directly
- [ ] Cache invalidated on settings change (host, token, allowSelfSignedCert)
- [ ] Manual refresh still probes all modes

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-04-03 | Identified during code review | Depends on auth-fallback refactor (#001) for clean implementation |
