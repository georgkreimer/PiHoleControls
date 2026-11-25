---
status: complete
priority: p1
issue_id: "017"
tags: [review, safety, testing]
dependencies: []
---

# Project Review Remediation

## Problem Statement
The full-project review found unsafe timed operations, tests sharing production storage,
an incomplete staged package extraction, incorrect API contracts, and fail-open releases.

## Findings
The working iOS branch and the parked temporary-allowlist branch need separate fixes.
The original temporary review artifact has expired; this record preserves the work scope.

## Recommended Action
Repair the shared client and macOS store with offline regression tests; isolate test
storage and app startup; fail release packaging on errors. Keep allowlist work separate.
The user approved disabling new temporary exceptions until server-side expiry exists.
Retain existing cleanup records, require explicit origin/ownership confirmation for old
records, and retry confirmed cleanup without redirecting it to another server.

## Acceptance Criteria
- [x] Server-managed timed disable and validated mutation responses.
- [x] Authentication/server/transport failures preserved; v5 connection test supported.
- [x] Required statistics validated rather than defaulting missing data to zero.
- [x] App/unit/UI tests isolated from real preferences, credentials and network startup.
- [x] Countdown never mutates another server; stale requests cannot overwrite new state.
- [x] All four shared-file deletions staged with extraction; staged build checked.
- [x] Archive/export failures stop release packaging; regression tests cover failures.
- [x] Parked branch blocks new exceptions and retains safe, retryable cleanup.
- [x] Parked branch validates domain ownership and recently-blocked API contracts.
- [x] Documentation and verification results recorded durably.

## Work Log
### 2026-11-23
Rechecked the unchanged dirty working tree. User authorized disabling new temporary
exceptions while retaining cleanup. No release, merge, push or commit requested.

Completed all 13 findings. Verification: 69 shared-package tests, 18 current app
tests, 77 parked-branch tests (85 parameter-expanded runs), six release tests in
each worktree, staged-snapshot compile, and iOS simulator build. All passed.
Details and limitations: `docs/reviews/2026-11-23-review-remediation.md`.
Parked fixes remain uncommitted in `.worktrees/temp-domain-allowlist`; no merge.
