---
status: complete
priority: p2
issue_id: "011"
tags: [code-review, security]
dependencies: []
---

# Session Cache Key Contains Raw API Token in Plaintext

## Problem Statement

The session cache key is `"\(baseURL.absoluteString)|\(token)"` (line 55-56). The raw token persists as a dictionary key in memory for up to 25 minutes. In a memory dump or crash report, the token would be discoverable.

## Findings

- **Identified by:** Security Sentinel
- **File:** `PiHoleControls/PiHoleClient.swift` lines 55-56

## Proposed Solutions

### Option A: Hash the cache key with SHA256
- **Effort:** Trivial (CryptoKit is available)
- **Risk:** Very Low

## Acceptance Criteria

- [ ] Cache key does not contain the raw token string
- [ ] Session cache still works correctly (same key for same host+token)

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-04-03 | Identified during code review | Defense-in-depth improvement |
