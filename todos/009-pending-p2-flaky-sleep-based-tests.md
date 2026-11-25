---
status: complete
priority: p2
issue_id: "009"
tags: [code-review, testing]
dependencies: []
---

# Tests Use Task.sleep for Synchronization -- Flaky and Slow

## Problem Statement

Every test in `PiHoleStoreTests.swift` uses `Task.sleep(nanoseconds:)` to wait for async operations. The retry-backoff test (line 69) sleeps for 8 seconds. On loaded CI runners, short sleeps (100ms) may not be enough; long sleeps make the suite slow.

**Why it matters:** Flaky tests erode confidence and slow development. The 8-second sleep alone makes the suite unreasonably slow.

## Findings

- **Identified by:** Architecture Strategist, Pattern Recognition
- **File:** `PiHoleControlsTests/PiHoleStoreTests.swift` lines 36, 53, 69, 94, 110, 120, 134, 150, 164

## Proposed Solutions

### Option A: Make async methods internal so tests can await directly
- **Pros:** Deterministic; no sleep needed; fast
- **Effort:** Small
- **Risk:** Very Low

### Option B: Inject retry delay as a parameter (zero-delay in tests)
- **Pros:** Retry tests complete instantly
- **Effort:** Small
- **Risk:** Very Low

### Option C: Both A and B
- **Effort:** Small
- **Risk:** Very Low

## Acceptance Criteria

- [ ] No `Task.sleep` in tests for synchronization purposes
- [ ] Test suite completes in < 5 seconds
- [ ] Tests are deterministic (no timing-dependent flakiness)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-04-03 | Identified during code review | |
