# fix: Legacy API 500 Error Handling

> **Created:** 2026-01-21
> **Type:** Bug
> **Complexity:** Medium

## Overview

The legacy Pi-hole v5 endpoint (`/admin/api.php`) is returning HTTP 500 for some users, causing refresh/enable/disable flows to fail. This plan focuses on capturing actionable diagnostics, validating the fallback logic, and ensuring the UI provides clear guidance when the legacy endpoint fails.

## Problem Statement / Motivation

When the app falls back to the legacy v5 API, the endpoint returns HTTP 500. The app surfaces a generic error and continues retrying, leaving users without a clear remediation path. We need to confirm why the legacy call fails, reduce unnecessary retries, and provide precise feedback so users can recover quickly.

## Proposed Solution

1. **Reproduce and capture diagnostics** for legacy requests (without exposing secrets), including endpoint, auth mode, and response metadata.
2. **Validate fallback decision logic** to ensure we only hit `/admin/api.php` when v6 endpoints are truly unavailable, and only with the correct auth scheme.
3. **Improve user-facing guidance** for legacy failures (e.g., suggest verifying Pi-hole version, API token type, and server health) while keeping sensitive payloads hidden.
4. **Add targeted tests** around legacy 500 behavior and retry boundaries.

## Current State Snapshot

- Legacy fallback is only triggered on a 404 from the v6 endpoint.
- Legacy errors are wrapped in `PiHoleError` without body previews for safety.
- Store retries all non-config errors, which may cause repeated 500 retries.

## Detailed Plan

### Diagnostics (Safe, Non-Secret)

- Add a structured diagnostic payload to `PiHoleError` for legacy requests:
  - `method`, `endpoint`, `statusCode`, `action` (status refresh vs enable/disable), `authMode`.
  - Keep empty when not legacy or when status is not 500.
- Ensure diagnostics are only included in error descriptions for the UI (no console logging).
- Confirm diagnostics do not contain hostnames if that is considered sensitive (use a redacted host or omit host entirely).

### Legacy Fallback Validation

- Assert fallback to legacy only occurs on v6 404 (no retries on 401/403/500 for v6).
- Ensure legacy requests use query token only; if the token format matches v6 app password, include hint in the error.

### User-Facing Guidance

- Replace the generic legacy 500 message with a multi-line action list:
  - Verify Pi-hole is v5 (legacy API) or upgrade to v6.
  - Confirm the API token is the legacy token (not an app password).
  - Check server health and that `/admin/api.php` is reachable.

### Retry Behavior

- Classify legacy 500 as non-retryable to prevent repeated loading loops.
- Keep retry behavior unchanged for transient network failures and timeouts.

### Tests

- Add `PiHoleStoreTests` coverage for a legacy 500 response:
  - Ensure error surfaces once and `isLoading` resets.
  - Ensure `withRetry` does not retry 500 for legacy endpoints.
- Add `PiHoleClientTests` (if exists) or extend store tests to verify fallback only on v6 404.

### Documentation / Notes

- Capture a single reproduction entry in this plan (no secrets):
  - `timestamp`, `action`, `endpoint`, `statusCode`, `authMode`, `result`.

## Technical Considerations

- **Legacy fallback path:** `PiHoleClient.fetchStatus` falls back to `requestLegacy` only for 404 from v6 (`PiHoleControls/PiHoleClient.swift:74`). Confirm the 500 is happening on the legacy endpoint, not the v6 path.
- **Retry behavior:** `PiHoleStore.withRetry` retries all errors except configuration/cancellation (`PiHoleControls/PiHoleStore.swift:225`). Consider whether 500s should be retried or surfaced immediately with guidance.
- **Error messaging:** `PiHoleClient.PiHoleError` excludes body previews for safety (`PiHoleControls/PiHoleClient.swift:654`). Diagnostics must remain sanitized.
- **Auth modes:** Legacy endpoint uses query token only (`PiHoleControls/PiHoleClient.swift:42`). If a v6 app password is provided, legacy may fail. We should detect and message this possibility.

## Acceptance Criteria

- [ ] A reproducible report exists for the 500 response (endpoint + action + timestamp) in the plan’s notes (no secrets). `plans/fix-legacy-api-500-error.md`
- [ ] Legacy fallback is confirmed to trigger only on v6 404, not on other errors. `PiHoleControls/PiHoleClient.swift`
- [ ] User-facing error for legacy 500 includes next steps (check Pi-hole version, verify API token type, confirm server health). `PiHoleControls/PiHoleClient.swift`
- [ ] Retry behavior for 500 is documented and, if adjusted, has tests. `PiHoleControls/PiHoleStore.swift`, `PiHoleControlsTests/PiHoleStoreTests.swift`
- [ ] Unit tests cover legacy 500 handling and ensure error surface does not loop indefinitely. `PiHoleControlsTests/PiHoleStoreTests.swift`

## Diagnostics Log (Sanitized)

| Timestamp | Action | Endpoint | Status | Auth Mode | Result |
| --- | --- | --- | --- | --- | --- |
| 2026-01-21 10:30 | status refresh | `/admin/api.php` | 500 | query token | Legacy call fails; guidance shown |

## Success Metrics

- 500 errors result in a single clear error message, not repeated retries that keep the UI in a loading loop.
- At least one automated test reproduces the 500 path and asserts correct error handling.
- Users report the 500 issue is actionable without needing Console.app logs.

## Dependencies & Risks

- **Dependency:** Access to a Pi-hole v5/v6 instance or mocked responses for 500 reproduction.
- **Risk:** Overly aggressive retry changes could reduce resilience for transient server failures.

## Implementation Notes

### Investigation Checklist

- [ ] Capture raw response metadata (status code, endpoint, request method) without body content. `PiHoleControls/PiHoleClient.swift`
- [ ] Confirm which action triggers the legacy call (status refresh vs enable/disable). `PiHoleControls/PiHoleStore.swift`
- [ ] Verify whether the user token is an app password vs legacy API token. `PiHoleControls/PiHoleClient.swift`

### Suggested Debug Snippet (Local Only)

```text
# Diagnostics only (do not ship in release builds)
# File: PiHoleControls/PiHoleClient.swift
# Log: method, endpoint, statusCode, auth mode used (no token)
```

## References & Research

### Internal References

- Legacy request builder: `PiHoleControls/PiHoleClient.swift:42`
- v6 fallback to legacy: `PiHoleControls/PiHoleClient.swift:74`
- Error description formatting: `PiHoleControls/PiHoleClient.swift:654`
- Retry logic: `PiHoleControls/PiHoleStore.swift:225`
- Existing 500 test coverage: `PiHoleControlsTests/PiHoleStoreTests.swift:56`

### External References

- Pi-hole API docs (error handling, 500s are rare): https://docs.pi-hole.net/api/
- Local API docs per Pi-hole instance: http://pi.hole/api/docs

## AI-Era Considerations

- Use AI to draft test cases and sanity-check retry boundaries, but confirm with a real Pi-hole instance before shipping.
- Flag any AI-generated diagnostics so they don’t accidentally log sensitive values.
