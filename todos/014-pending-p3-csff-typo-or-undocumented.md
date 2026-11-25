---
status: complete
priority: p3
issue_id: "014"
tags: [code-review, quality]
dependencies: []
---

# `csff` Field in AuthSession -- Typo or Undocumented Server Quirk

## Problem Statement

`PiHoleClient.swift` line 384 defines `let csff: String?` in the `AuthSession` struct alongside `let csrf: String?`. Line 398 uses `decoded.session.csff ?? decoded.session.csrf`. If `csff` is an actual Pi-hole API field name (server-side typo), it should be documented. If it's a code typo, one field is dead code.

## Findings

- **Identified by:** Architecture Strategist, Pattern Recognition
- **File:** `PiHoleControls/PiHoleClient.swift` lines 384, 398

## Proposed Solutions

### Option A: Add a comment explaining the `csff` field
- If intentional, use `CodingKeys` to map both server names to one property
- If typo, remove `csff` and fix the fallback

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-04-03 | Identified during code review | |
