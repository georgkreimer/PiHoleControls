# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

```bash
# Build for macOS
xcodebuild -scheme PiHoleControls -destination "platform=macOS" build

# Run all tests
xcodebuild test -scheme PiHoleControls -destination "platform=macOS"

# Run unit tests only
xcodebuild test -scheme PiHoleControls -destination "platform=macOS" -only-testing:PiHoleControlsTests

# Run UI tests only
xcodebuild test -scheme PiHoleControls -destination "platform=macOS" -only-testing:PiHoleControlsUITests

# Run a single test by name
xcodebuild test -scheme PiHoleControls -destination "platform=macOS" -only-testing:PiHoleControlsTests/PiHoleStoreTests/fetchStatusBlockingEnabled

# Build release zip
./scripts/release.sh

# Build and upload to GitHub Releases (requires `gh` CLI)
./scripts/release.sh --upload
```

Requires Xcode 15+ and macOS 14+.

## Architecture Overview

macOS menu bar app that controls Pi-hole DNS blocking. Supports both Pi-hole v5 (legacy API) and v6 (modern REST API).

### Core Components

**PiHoleStore** (`PiHoleStore.swift`) — `@MainActor` ObservableObject that owns all UI state and settings. Manages auto-refresh polling (20s), network monitoring via `NWPathMonitor`, countdown timers for timed disable, and retry with exponential backoff. Accepts a `ClientFactory` closure for dependency injection in tests.

**PiHoleClient** (`PiHoleClient.swift`) — Stateless struct implementing `PiHoleClientProtocol`. Tries v6 endpoints first (`/api/dns/blocking`), falls back to v5 legacy API (`/admin/api.php`) on 404. Supports session-based auth (with CSRF), Bearer token, Token header, and query parameter auth modes. Sessions are cached in `PiHoleSessionCache` (a Swift actor with 25-min TTL) and auto-refreshed on 401/403.

**StatusItemController** (`StatusItemController.swift`) — Owns the `NSStatusItem` and `NSPopover`. Left-click toggles blocking; right-click opens the popover. Uses a custom `StatusItemView` (AppKit `NSView`) for the menu bar icon with countdown timer overlay. Observes store via Combine.

**ContentView** (`ContentView.swift`) — SwiftUI popover with sliding navigation between status and settings views. Fixed 300pt width. Uses `HeightReader` to animate height transitions between views. Popover dismissal is threaded through a custom `dismissMenu` SwiftUI `EnvironmentKey`.

**SettingsView** (`SettingsView.swift`) — Standalone SwiftUI settings window (opened via macOS Settings menu). Contains connection test that calls `fetchStatus(allowLegacyFallback: false)` to verify v6 connectivity.

### Data Flow

1. `PiHoleControlsApp` uses `@NSApplicationDelegateAdaptor` to bridge to `AppDelegate`
2. `AppDelegate` creates `PiHoleStore` and `StatusItemController` on launch
3. `StatusItemController` observes store's `@Published` properties via Combine
4. User actions call `PiHoleStore` methods, which create ephemeral `PiHoleClient` instances
5. Results update `@Published` properties, triggering UI updates

### UI Layer

Hybrid AppKit + SwiftUI. The menu bar icon is pure AppKit (`NSStatusItem` + custom `NSView`). The popover content and settings window are SwiftUI hosted in `NSHostingController`. The popover is dismissed via a closure injected through `MenuDismissEnvironment`.

### Testing

Tests use **Swift Testing** framework (`import Testing`, `@Test`, `@Suite`, `#expect`), not XCTest. The `PiHoleClientProtocol` enables mock injection — `MockPiHoleClient` tracks call counts and configurable responses. `PiHoleStore` accepts a `clientFactory` closure to swap in mocks. Tests use `Task.sleep` to wait for async operations.

### API Token Storage

Tokens are stored in macOS Keychain via `KeychainHelper` (service: `com.littleappventures.PiHoleControls`). On first launch, tokens migrate from `@AppStorage` (UserDefaults) to Keychain automatically.
