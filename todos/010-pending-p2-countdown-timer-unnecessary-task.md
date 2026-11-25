---
status: complete
priority: p2
issue_id: "010"
tags: [code-review, performance]
dependencies: []
---

# Countdown Timer Creates Unnecessary Task on Every Tick

## Problem Statement

The countdown timer (PiHoleStore.swift lines 354-368) fires every 1 second and creates a `Task { @MainActor }` each tick. Since the timer runs on `RunLoop.main` and PiHoleStore is `@MainActor`, the Task wrapper is unnecessary -- the callback is already on the main thread. For a 60-minute disable, that's 3600 unnecessary task allocations.

## Findings

- **Identified by:** Performance Oracle
- **File:** `PiHoleControls/PiHoleStore.swift` lines 354-368

## Proposed Solutions

### Option A: Use `MainActor.assumeIsolated` (Swift 5.10+)
- **Effort:** Trivial
- **Risk:** Very Low

## Acceptance Criteria

- [ ] Countdown timer does not allocate a Task on each tick
- [ ] Timer still correctly updates `remainingDisableSeconds`

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-04-03 | Identified during code review | |
