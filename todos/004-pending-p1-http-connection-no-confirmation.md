---
status: complete
priority: p1
issue_id: "004"
tags: [code-review, security]
dependencies: []
---

# HTTP Connections Allowed Without User Confirmation

## Problem Statement

The app allows plaintext HTTP connections without requiring explicit user confirmation. API tokens are transmitted in cleartext via Bearer headers, Token headers, query parameters, and POST bodies. The self-signed cert toggle has a confirmation dialog, but HTTP (a more common misconfiguration) does not.

The UI does show a red "Insecure: HTTP connections are unencrypted" warning label, but there is no confirmation dialog blocking the save.

Additionally, for the legacy v5 API, the token is appended as a URL query parameter (`?auth=<token>`), which persists in server access logs even over HTTPS.

**Why it matters:** On shared/untrusted networks, an attacker with passive packet capture sees the full API token and all Pi-hole control commands in cleartext.

## Findings

- **Identified by:** Security Sentinel
- **File:** `PiHoleControls/PiHoleClient.swift` lines 182, 248-249
- **File:** `PiHoleControls/SettingsView.swift` lines 112, 124
- **Mitigating factor:** Red warning label already shown in UI

## Proposed Solutions

### Option A: Add confirmation dialog for HTTP hosts (like self-signed cert)
- **Pros:** Consistent UX pattern; low effort; users make informed choice
- **Cons:** Adds friction for users on trusted local networks
- **Effort:** Small
- **Risk:** Very Low

### Option B: Default host to `https://` and show `https://` first in examples
- **Pros:** Nudges users toward secure defaults; no friction for HTTPS users
- **Cons:** Doesn't prevent HTTP usage entirely
- **Effort:** Small
- **Risk:** Very Low

### Option C: Both A and B
- **Pros:** Defense in depth
- **Effort:** Small
- **Risk:** Very Low

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] HTTP connections require explicit user acknowledgment (dialog or similar)
- [ ] Examples show `https://` first
- [ ] Default host uses `https://` scheme or is empty

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-04-03 | Identified during code review | Self-signed cert already has this pattern; HTTP should match |
