# Full-Project Review Remediation

## Scope

The 13 findings from the full-project/unmerged-branch review are addressed below.
Existing staged iOS work was preserved. Only the four already-deleted shared source
files were added to the index to make the extraction self-contained. New fixes are
uncommitted; nothing was merged, pushed, released, or deployed to a physical device.

Working copies:
- `feat/ios-companion-app`: `/Users/gkreimer/Development/PiHoleControls`
- `feat/temp-domain-allowlist`: `/Users/gkreimer/Development/PiHoleControls/.worktrees/temp-domain-allowlist`

The parked branch remains separate. Its shared client/store/release fixes were
also applied there without importing the iOS package extraction. The older
`refactor/code-quality-remediation` branch was inspected and left unchanged;
it diverges from the newer main implementation and is not a merge candidate as-is.

## Resolution Matrix

| # | Finding | Resolution and regression coverage |
|---|---|---|
| 1 | Timed disable sends `duration` instead of `timer` | Canonical v6 POST uses `blocking` and `timer`. Countdown expiry only refreshes; it never enables blocking. API payload and clock-driven store tests cover this. |
| 2 | Tests overwrite production credentials/preferences | Injected UserDefaults, TokenStorage, clock, and network-monitor switch. Unique test suites and in-memory credentials; app startup is isolated under XCTest/UI-test launch arguments. |
| 3 | Staged extraction retains old types | Staged the four existing deletions. Exported the index and successfully built it for testing without executing its older tests. |
| 4 | Failed/expired allowlist cleanup records are discarded | Preserve all records until confirmed server removal and successful journal persistence. Atomic file journal migrates old preferences; restart, offline, corrupt-data, and write-failure tests cover retention. |
| 5 | Local expiry cannot guarantee removal after crash | Per user decision, creation is disabled in the store and UI. No new POST can originate from that feature. UI and README state cleanup requires the running app and server connectivity. |
| 6 | Delayed operations target newly configured server | Configuration identity discards stale UI results, stops old countdowns, and prevents stale retries. Confirmed cleanup captures its original client and only runs for the recorded origin. Old records require explicit server confirmation. |
| 7 | HTTP 201 may hide duplicate insertion failure | Domain insertion requires a matching `processed.success` entry and no errors. Legacy records have unknown ownership and require explicit removal confirmation instead of automatic deletion. |
| 8 | Speculative mutations overwrite meaningful errors | Removed guessed PUT/alternate paths. Preserve HTTP/auth/transport failures; only a missing endpoint allows v5 fallback. Cancellation is not retried. |
| 9 | Incorrect recent-query filter and fallback schema | Uses `upstream=blocklist`, filters recognized blocked statuses, decodes fallback string arrays with `count`, and represents unavailable timestamps as nil. Errors are not silently converted into an empty list. |
| 10 | Settings connection test rejects v5 | Uses the normal v6-to-v5 status path; mock regression asserts legacy fallback is enabled. |
| 11 | Legacy mutations accept HTTP 200 error bodies | Require a decoded response confirming the requested enabled/disabled status. Empty, malformed, and wrong-status bodies fail. |
| 12 | Release script packages failed archive/export output | Fail immediately, retain logs, remove archive-copy fallback, and verify executable/signature before ZIP or publishing. Six stubbed failure/success tests exercise the script, including `--upload` failure paths. |
| 13 | Missing statistics appear as valid zeroes | Required counters must decode; missing/FTL-down responses fail while genuine zero statistics succeed for v5 and v6. |

Additional fixes: removed the Info.plist copy-resource warning, isolated the mutable
mock on MainActor, corrected deployment/test documentation, and added the iOS
local-network purpose string and HTTP transport configuration. The generated
simulator app's Info.plist was inspected to confirm those keys are present.

## Verification

- `swift test --package-path PiHoleKit --scratch-path /tmp/pihole-fixes-swift`: 69 tests passed.
- Current macOS `PiHoleControlsTests`: 18 tests passed.
- Parked branch `PiHoleControlsTests`: 77 tests passed (85 parameter-expanded executions), zero failures or runtime warnings.
- `python3 scripts/tests/test_release.py`: six tests passed in each worktree; no GitHub publication.
- iOS simulator build: passed with signing disabled.
- Staged-only macOS `build-for-testing`: passed. The older staged tests were deliberately not executed because storage isolation is part of the new unstaged fixes.
- `git diff --check`: passed in both worktrees.

API regression tests failed against the previous implementations before the
corresponding fixes. Release tests likewise reproduced the fail-open behavior.
All network tests use URLProtocol fixtures or mock clients; no live Pi-hole
configuration or production credentials were read or changed by these tests.

Not performed: physical-iPhone deployment, live Pi-hole mutations, UI interaction
testing, a signed release archive/export, or crash/power-loss fault injection.
The iOS target is still a scaffold; this review does not implement its pending UI
and widgets. Existing legacy cleanup records require user review on the original
server; unknown origin/ownership must never be guessed. Atomic persistence enables
retry after restart but does not provide server-side expiry while the app is down.

## API References

- [Pi-hole blocking contract](https://raw.githubusercontent.com/pi-hole/FTL/master/src/api/docs/content/specs/dns.yaml)
- [Pi-hole query filtering](https://raw.githubusercontent.com/pi-hole/FTL/master/src/api/docs/content/specs/queries.yaml)
- [Pi-hole domain mutation results](https://raw.githubusercontent.com/pi-hole/FTL/master/src/api/docs/content/specs/domains.yaml)
- [Pi-hole recent-blocked statistics](https://raw.githubusercontent.com/pi-hole/FTL/master/src/api/docs/content/specs/stats.yaml)
