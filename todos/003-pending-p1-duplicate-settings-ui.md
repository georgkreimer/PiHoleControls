---
status: complete
priority: p1
issue_id: "003"
tags: [code-review, quality, architecture]
dependencies: []
---

# Duplicate Settings UI Between ContentView.swift and SettingsView.swift

## Problem Statement

`SettingsView.swift` (484 lines) is a standalone macOS Settings window that duplicates nearly everything from `SettingsContentView` inside `ContentView.swift` (lines 374-811):

| Component | ContentView.swift | SettingsView.swift |
|---|---|---|
| `SettingsTextField` | Lines 815-861 | Lines 344-374 |
| `SettingsSecureField` | Lines 865-925 | Lines 378-427 |
| `TestState` enum | Line 381 | Line 18 |
| `runConnectionTest()` | Lines 782-804 | Lines 438-459 |
| `isHttpHost` | Lines 385-389 | Lines 432-436 |
| Self-signed cert toggle | Lines 561-606 | Lines 131-171 |

Both `runConnectionTest()` implementations also bypass the store's DI by creating `PiHoleClient` directly (untestable).

**Why it matters:** Bug fixes in one won't propagate to the other. Two complete settings interfaces maintained in parallel is a maintenance hazard. The direct `PiHoleClient` creation bypasses the protocol/mock abstraction.

## Findings

- **Identified by:** Architecture Strategist, Pattern Recognition, Code Simplicity (3/5 agents)
- **Files:** `PiHoleControls/ContentView.swift`, `PiHoleControls/SettingsView.swift`
- **Evidence:** ~400 lines of functionally duplicated code

## Proposed Solutions

### Option A: Delete SettingsView.swift, reuse SettingsContentView in Settings scene
- **Pros:** Eliminates ~400 lines; single source of truth; immediate win
- **Cons:** May need styling adjustments for the standalone window context
- **Effort:** Small-Medium
- **Risk:** Low

### Option B: Extract shared components into a SharedSettingsComponents.swift
- **Pros:** Both UIs stay but share implementation; allows styling differences
- **Cons:** Still two entry points to maintain
- **Effort:** Medium
- **Risk:** Low

### Option C: Move connection test into PiHoleStore, share form components
- **Pros:** Fixes both the duplication AND the DI bypass; `testConnection()` becomes testable
- **Cons:** Larger refactor
- **Effort:** Medium
- **Risk:** Low

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] Settings UI code exists in only one place (or shares common components)
- [ ] Connection test goes through the store's client factory (testable)
- [ ] Both the popover settings and Settings window work correctly

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-04-03 | Identified during code review | Simplicity agent estimated ~484 lines removable |
