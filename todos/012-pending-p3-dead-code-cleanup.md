---
status: complete
priority: p3
issue_id: "012"
tags: [code-review, quality, cleanup]
dependencies: ["001"]
---

# Dead Code and Unnecessary Wrappers Cleanup

## Problem Statement

Several pieces of dead or redundant code exist:

1. `ensureSessionAuth()` (PiHoleClient.swift line 104-109) -- never called anywhere
2. `sendRequest()` (lines 209-224) -- trivial wrapper around `sendRequestUsing()` that only adds `baseURL`
3. `statusPaths` (line 404) -- single-element array with unnecessary `for` loop
4. `menuBarTitle` (PiHoleStore.swift lines 131-146) -- returns empty string in most branches; timer text is computed independently in StatusItemController
5. `PiHoleControlsTests.swift` -- empty Xcode template with no real tests
6. Redundant Keychain re-read in `requireClientOrFail()` (PiHoleStore.swift lines 198-203) -- token already loaded in `init()`

## Findings

- **Identified by:** Code Simplicity, Architecture Strategist, Performance Oracle

## Proposed Solutions

### Option A: Delete all identified dead code
- **Effort:** Small
- **Risk:** Very Low

## Acceptance Criteria

- [ ] `ensureSessionAuth()` removed
- [ ] `sendRequest` wrapper inlined or removed
- [ ] `statusPaths` array replaced with direct path usage
- [ ] `menuBarTitle` either used or removed (resolve duplication with StatusItemController)
- [ ] Empty test file deleted
- [ ] Redundant Keychain re-read removed

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-04-03 | Identified during code review | |
