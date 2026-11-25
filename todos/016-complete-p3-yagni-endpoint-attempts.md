---
status: complete
priority: p3
issue_id: "016"
tags: [code-review, quality, simplification]
dependencies: ["001"]
---

# YAGNI: enableV6/disableV6 Try 3 Endpoint/Method Combos Speculatively

## Problem Statement

`enableV6()` and `disableV6()` each define 3 attempt tuples (POST, PUT, and alternate path) for endpoints that Pi-hole v6 may or may not support. This triples the complexity of the auth-fallback loop. Additionally, `decodeV6Status()` handles 6 string formats for a field that returns a boolean.

If only one endpoint/method combination works in practice, the other two are speculative code that adds complexity.

## Findings

- **Identified by:** Code Simplicity
- **File:** `PiHoleControls/PiHoleClient.swift` lines 558-562, 620-624, 327-362

## Proposed Solutions

### Option A: Determine which endpoint works and keep only that one
- Test against real Pi-hole v6 to identify the working endpoint
- Remove speculative alternatives
- **Effort:** Small (requires manual testing)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-04-03 | Identified during code review | Resolves naturally if auth-fallback is refactored (#001) |
| 2026-11-23 | Removed guessed PUT and alternate mutation endpoints on both active worktrees | Official v6 contract uses POST /api/dns/blocking with blocking and timer; offline fixtures prove errors cannot be overwritten by later 404s. Kept status decoding compatibility: v6 returns an enabled/disabled string, not exclusively a boolean. |
