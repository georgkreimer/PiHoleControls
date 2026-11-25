---
status: complete
priority: p1
issue_id: "002"
tags: [code-review, quality, correctness]
dependencies: []
---

# enableBlocking/disableBlocking Silently Swallow V6 Errors

## Problem Statement

`enableBlocking()` (line 731) and `disableBlocking()` (line 755) use `try?` to call v6 methods, swallowing ALL errors and always falling through to the legacy v5 path:

```swift
if (try? await enableV6()) == true { return }
```

This is inconsistent with `fetchStatus()` (lines 690-701) which correctly only falls back to legacy on 404 and re-throws other errors. On a v6 server, genuine errors (auth failures, 500s, timeouts) are masked, and users see misleading legacy-API errors.

**Why it matters:** Users on Pi-hole v6 will see confusing "legacy API" errors when their actual issue is authentication or server health. This is a correctness bug.

## Findings

- **Identified by:** Architecture Strategist, Pattern Recognition, Performance Oracle, Security Sentinel
- **File:** `PiHoleControls/PiHoleClient.swift` lines 729-731, 753-755
- **Evidence:** Compare with `fetchStatus()` at lines 690-701 which has correct 404-specific fallback

## Proposed Solutions

### Option A: Match fetchStatus pattern with do/catch
- **Pros:** Consistent error handling across all three methods; only falls back on 404
- **Cons:** None
- **Effort:** Small
- **Risk:** Very Low

```swift
do {
    try await enableV6()
    return
} catch let err as PiHoleError {
    if case .invalidResponse(let sc, _, _, _) = err, sc == 404 {
        // fall through to legacy
    } else {
        throw err
    }
}
```

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [x] `enableBlocking` and `disableBlocking` only fall back to legacy on 404
- [x] Non-404 v6 errors are surfaced to the user
- [x] All existing tests pass

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-04-03 | Identified during code review | 4/5 agents flagged this independently |
| 2026-11-23 | Closed the remaining error masking inside speculative mutation/auth loops | Regression fixtures cover 401, 403, 500, 503 and transport failure on both worktrees. |
