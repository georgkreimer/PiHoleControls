---
status: complete
priority: p3
issue_id: "013"
tags: [code-review, quality, simplification]
dependencies: []
---

# PiHoleSessionCache Over-Engineered for Single-Connection App

## Problem Statement

`PiHoleSessionCache` supports 10 entries with TTL expiration and LRU-style eviction. The app connects to exactly one Pi-hole instance. A single optional `Session?` with a timestamp would suffice.

Also, `cleanupExpired()` is called on both `get` and `set`, but `get` already checks the specific key's TTL. The cleanup on `get` is redundant.

## Findings

- **Identified by:** Code Simplicity, Performance Oracle
- **File:** `PiHoleControls/PiHoleSessionCache.swift`
- **Estimated reduction:** ~30 lines

## Proposed Solutions

### Option A: Replace with a simple single-session holder
- **Effort:** Small
- **Risk:** Very Low

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-04-03 | Identified during code review | YAGNI violation |
