---
status: complete
priority: p3
issue_id: "015"
tags: [code-review, testing]
dependencies: ["009"]
---

# No Test Coverage for PiHoleClient, KeychainHelper, or PiHoleSessionCache

## Problem Statement

The test suite contains only `PiHoleStoreTests` (11 test cases). The following components have zero test coverage:

- **PiHoleClient** -- the most complex component (800+ lines, multiple auth modes, v5/v6 fallback, session retry). No tests for URL construction, auth cascading, error mapping.
- **PiHoleSessionCache** -- actor-based TTL cache with eviction logic. Pure logic, easy to test.
- **KeychainHelper** -- Keychain read/write/delete operations.

## Findings

- **Identified by:** Architecture Strategist
- **Files:** `PiHoleControlsTests/` contains only `PiHoleStoreTests.swift` and an empty template

## Proposed Solutions

### Option A: Add unit tests incrementally
- Start with `PiHoleSessionCache` (pure logic, no dependencies)
- Then `PiHoleClient` URL construction and error mapping (extract URLSession as injectable)
- `KeychainHelper` can use a test-specific service name
- **Effort:** Large (but incremental)
- **Risk:** Very Low

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-04-03 | Identified during code review | PiHoleClient is highest-complexity, lowest-coverage component |
