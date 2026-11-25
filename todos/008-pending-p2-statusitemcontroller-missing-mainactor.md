---
status: complete
priority: p2
issue_id: "008"
tags: [code-review, quality, concurrency]
dependencies: []
---

# StatusItemController Missing @MainActor Annotation

## Problem Statement

`StatusItemController` (line 14) is a plain `final class` that directly manipulates `NSStatusItem`, `NSPopover`, and custom `NSView` subclasses. All AppKit UI work must happen on the main thread. While it works in practice (created from `applicationDidFinishLaunching` on main thread, Combine sink uses `.receive(on: RunLoop.main)`), the compiler cannot verify this contract.

**Why it matters:** Future changes could introduce off-main-thread access without compiler warnings.

## Findings

- **Identified by:** Architecture Strategist, Pattern Recognition
- **File:** `PiHoleControls/StatusItemController.swift` line 14

## Proposed Solutions

### Option A: Add @MainActor to the class
- **Effort:** Trivial
- **Risk:** Very Low -- may require minor adjustments for strict concurrency

## Acceptance Criteria

- [ ] `StatusItemController` annotated with `@MainActor`
- [ ] Compiles cleanly with strict concurrency checking

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-04-03 | Identified during code review | |
