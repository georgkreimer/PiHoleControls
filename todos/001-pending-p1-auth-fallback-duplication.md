---
status: complete
priority: p1
issue_id: "001"
tags: [code-review, architecture, quality]
dependencies: []
---

# Auth-Fallback Code Duplication in PiHoleClient (~270 lines)

## Problem Statement

`fetchStatusV6()`, `enableV6()`, and `disableV6()` in `PiHoleClient.swift` contain nearly identical auth-cascade logic: try session auth first, fall back through bearer/tokenHeader/queryToken, handle 401/403/404 status codes, build error previews. This pattern is copy-pasted three times totaling ~270 lines. `enableV6` and `disableV6` are almost line-for-line identical (lines 556-614 vs 616-675).

Additionally, the body preview pattern `String(data: data, encoding: .utf8).map { String($0.prefix(300)) }` is repeated ~16 times throughout the file.

**Why it matters:** Any bug fix or auth-mode change must be applied in 3 places. The high cyclomatic complexity of `fetchStatusV6` alone makes it hard to reason about. This is the #1 maintainability issue in the codebase.

## Findings

- **Identified by:** Architecture Strategist, Pattern Recognition, Code Simplicity, Performance Oracle (all 4 agents flagged this independently)
- **File:** `PiHoleControls/PiHoleClient.swift` lines 402-675
- **Evidence:** `enableV6` (60 lines) and `disableV6` (60 lines) differ only in payload and endpoint tuples

## Proposed Solutions

### Option A: Extract a generic `requestV6WithAuthFallback` method
- **Pros:** Single auth-cascade implementation; three callers become thin wrappers (~5-10 lines each); easier to test
- **Cons:** Requires careful generalization of the return type handling
- **Effort:** Medium
- **Risk:** Low -- the logic is already identical, just needs parameterization

### Option B: Extract auth-cascade into a separate AuthStrategy type
- **Pros:** Full separation of concerns; auth logic becomes independently testable
- **Cons:** May be over-engineering for a utility app
- **Effort:** Large
- **Risk:** Medium

### Option C: Keep current structure but extract `bodyPreview` helper and error factory
- **Pros:** Minimal change; immediate readability improvement
- **Cons:** Core duplication remains
- **Effort:** Small
- **Risk:** Very Low

## Recommended Action

<!-- Fill during triage -->

## Technical Details

- **Affected files:** `PiHoleControls/PiHoleClient.swift`
- **Estimated LOC reduction:** ~180-200 lines
- **Also extract:** `bodyPreview()` helper (eliminates 16 repetitions), delete unused `ensureSessionAuth()` (line 104), inline trivial `sendRequest` wrapper (lines 209-224)

## Acceptance Criteria

- [ ] Single method encapsulates the "try session, fall back to bearer/tokenHeader/queryToken" pattern
- [ ] `fetchStatusV6`, `enableV6`, `disableV6` are thin wrappers (<15 lines each)
- [ ] Body preview extraction repeated 0 times (helper method used instead)
- [ ] All existing tests pass
- [ ] Dead code `ensureSessionAuth()` removed

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-04-03 | Identified during code review | Flagged by 4/5 review agents as highest-impact issue |

## Resources

- PiHoleClient.swift lines 402-675
