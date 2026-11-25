---
status: complete
priority: p2
issue_id: "006"
tags: [code-review, security]
dependencies: []
---

# Self-Signed Cert Bypass Accepts All Certificates Without Host Check

## Problem Statement

The `IgnoreSelfSignedCertificateDelegate` (line 780-791) accepts ALL server certificates unconditionally when `allowSelfSignedCert` is enabled. It does not verify the certificate's CN/SAN matches the configured Pi-hole host. The URLSession is also a static singleton, persisting for the entire app lifetime.

**Why it matters:** Vulnerable to MITM attacks when enabled. Any certificate from any host is accepted.

## Findings

- **Identified by:** Security Sentinel
- **File:** `PiHoleControls/PiHoleClient.swift` lines 678-686, 780-791
- **Mitigating factor:** Requires explicit user confirmation via destructive alert dialog

## Proposed Solutions

### Option A: Verify challenge host matches configured Pi-hole host
- **Pros:** Narrows the bypass to only the intended server
- **Cons:** Requires passing host to the delegate
- **Effort:** Small
- **Risk:** Low

### Option B: Trust-on-first-use (TOFU) -- pin cert on first successful connection
- **Pros:** Strongest security improvement
- **Cons:** More complex; needs cert storage
- **Effort:** Large
- **Risk:** Medium

## Recommended Action

<!-- Fill during triage -->

## Acceptance Criteria

- [ ] Self-signed cert bypass only accepts certificates for the configured Pi-hole host
- [ ] Other hosts still use standard certificate validation

## Work Log

| Date | Action | Learnings |
|------|--------|-----------|
| 2026-04-03 | Identified during code review | |
