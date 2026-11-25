# iOS Companion App — Requirements

**Date:** 2026-04-24
**Status:** Draft
**Scope:** Standard

## Problem

The macOS menu bar app only works when you're at your Mac. Pi-hole control is most useful when it's always accessible — from the couch, on mobile data (via Tailscale/WireGuard), or anywhere away from the desk. There's no native iOS app that talks to Pi-hole v5/v6 APIs with the same auth flexibility this project already supports.

## Core Outcome

A native iOS app that lets you monitor and control your Pi-hole from anywhere your phone can reach it (local network or VPN), with a home screen widget for at-a-glance status.

## Users

- Same user as the macOS app: a self-hosted Pi-hole operator with Tailscale or similar VPN for remote access.

## Scope

### In Scope (v1)

1. **Blocking toggle** — See current blocking status (enabled/disabled). Toggle on/off. Timed disable with configurable default duration.
2. **Stats dashboard** — Queries today, queries blocked today, block percentage, top blocked domain. Pulled from Pi-hole summary API.
3. **Settings** — Host, API token (Keychain-stored), self-signed cert toggle, default disable duration. Connection test button.
4. **Home screen widget** — Small widget: blocking status icon + blocked count. Medium widget: adds block percentage and top blocked domain.
5. **Lock screen widget** — Blocking status indicator (on/off).
6. **Pi-hole v5 + v6 support** — Same dual-API strategy as macOS app.
7. **Multiple Pi-hole instances** — Support configuring 2+ Pi-holes (e.g., primary + secondary). Toggle blocking on all at once.

### Deferred

- Query log browsing
- Temporary domain allowlist (exists on macOS feature branch, port later)
- Push notifications for Pi-hole status changes
- Apple Watch app
- Shortcuts/Siri integration

### Non-Goals

- Relay server or cloud proxy — app talks directly to Pi-hole over local network or VPN
- Pi-hole administration (group management, DHCP, DNS settings)
- App Store distribution in v1 (personal use, TestFlight or ad-hoc)

## Project Structure

### Shared Code (both targets)

These files are already platform-agnostic and will be added to both the macOS and iOS targets:

- `PiHoleClient.swift` — API client
- `PiHoleClientProtocol.swift` — Protocol abstraction
- `PiHoleStore.swift` — State management (needs minor adaptation for multi-instance)
- `PiHoleSessionCache.swift` — Session caching
- `KeychainHelper.swift` — Secure token storage

### New iOS Code

- `PiHoleControls-iOS/` directory for iOS-specific files
- iOS app entry point (`PiHoleControlsIOSApp.swift`)
- `DashboardView.swift` — Main screen: status toggle + stats cards
- `SettingsView.swift` — iOS-native settings (NavigationStack)
- `ServerConfigView.swift` — Add/edit Pi-hole server configuration
- `PiHoleControlsWidget/` — WidgetKit extension target

### New Widget Target

- `PiHoleControlsWidget` — WidgetKit extension
- Shared App Group for passing data between app and widget
- `TimelineProvider` that refreshes on a schedule (15-30 min) and on-demand after toggle actions

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Project structure | New iOS target in same .xcodeproj | Simplest sharing, one repo, shared build settings |
| Data sharing (app ↔ widget) | App Group + UserDefaults suite | Standard WidgetKit pattern, no need for Core Data |
| Multi-instance | Array of server configs in Keychain + UserDefaults | Simple, no database needed for 2-3 servers |
| Credential storage | Keychain (same as macOS) | Already have KeychainHelper, works on iOS |
| Navigation | NavigationStack | Modern iOS navigation, fits the 3-screen depth |
| Minimum iOS version | iOS 17 | WidgetKit improvements, modern SwiftUI features |

## UI Screens

### 1. Dashboard (main screen)

- Large blocking status indicator (shield icon, colored green/red)
- Toggle button (enable/disable with timed disable option)
- Stats cards row: Queries Today | Blocked Today | Block %
- Server name/address shown at top
- Pull-to-refresh
- If multiple servers configured: segmented control or tab to switch

### 2. Settings

- List of configured Pi-hole servers (add/edit/delete)
- Default disable duration picker
- App info / version

### 3. Server Configuration (push from Settings)

- Host field
- API token field (secure entry)
- Self-signed certificate toggle
- Test Connection button

### 4. Widgets

- **Small (home screen):** Shield icon (green/red) + "42 blocked" count
- **Medium (home screen):** Shield icon + blocked count + block % + "Top: ads.example.com"
- **Lock screen (circular):** Shield icon only, colored by status

## Success Criteria

- Can toggle Pi-hole blocking from iPhone over Tailscale
- Stats update on pull-to-refresh and auto-refresh when app is foregrounded
- Widget shows current blocking status, refreshes within 30 minutes
- Connection test works for both v5 and v6 Pi-holes
- Credentials stored securely in Keychain, persist across app updates

## Open Questions

1. **Multi-instance toggle behavior:** Per-server. Each Pi-hole is toggled independently from its own dashboard view.
2. **Widget refresh strategy:** WidgetKit controls refresh budgets. Should the widget attempt a live API call in TimelineProvider, or only read cached data from the app? (Recommend: live API call with cached fallback.)
