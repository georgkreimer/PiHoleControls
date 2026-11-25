---
status: complete
priority: p2
issue_id: "007"
tags: [code-review, quality, ux]
dependencies: []
---

# Default Host "pi.hole" Has No Scheme -- Poor First-Run Experience

## Problem Statement

`PiHoleStore.host` defaults to `"pi.hole"` (line 12) which has no `http://` or `https://` scheme. `PiHoleClient.init` rejects hosts without a scheme, so `makeClient()` returns `nil` on fresh install. However, `isConfigured` returns `true` because the host is non-empty. Users see "Invalid host. Include http:// or https://..." instead of a clean "not configured" prompt.

The UI examples also show `http://` first, nudging users toward insecure connections.

**Why it matters:** Confusing first-run experience; users see an error that looks like a bug rather than a setup prompt.

## Findings

- **Identified by:** Architecture Strategist, Security Sentinel
- **File:** `PiHoleControls/PiHoleStore.swift` line 12
- **File:** `PiHoleControls/SettingsView.swift` line 112

## Proposed Solutions

### Option A: Change default to empty string `""`
- **Pros:** `isConfigured` returns false; shows proper "not configured" message
- **Effort:** Trivial
- **Risk:** Very Low

### Option B: Change default to `"https://pi.hole"`
- **Pros:** Functional default; nudges toward HTTPS
- **Effort:** Trivial
- **Risk:** Very Low

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] Fresh install shows appropriate "configure settings" message, not an error
- [ ] UI examples show `https://` first

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-04-03 | Identified during code review | |
