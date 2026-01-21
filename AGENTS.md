# Repository Guidelines

These notes keep contributions consistent for the Pi-hole macOS menu bar controller. Favor small, focused changes and update this guide if the workflow shifts.

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

# Build release and create zip
./scripts/release.sh

# Build and upload to GitHub Releases
./scripts/release.sh --upload
```

For development, open `PiHoleControls.xcodeproj` in Xcode and run with the PiHoleControls scheme on "My Mac".

## Architecture Overview

This is a macOS menu bar app that controls Pi-hole DNS blocking. The app supports both Pi-hole v5 (legacy API) and v6 (modern REST API).

### Core Components

**PiHoleStore** (`PiHoleStore.swift`) - Central state manager marked `@MainActor`. Holds all UI state (`isBlockingEnabled`, `isLoading`, `lastError`, `remainingDisableSeconds`) and settings (`host`, `token`, `allowSelfSignedCert`). Manages auto-refresh polling (20s interval), network monitoring via `NWPathMonitor`, and countdown timers for timed disable. Uses retry logic with exponential backoff for network operations.

**PiHoleClient** (`PiHoleClient.swift`) - Stateless API client handling all Pi-hole communication. Attempts v6 API endpoints first (`/api/dns/blocking`), falling back to v5 legacy API (`/admin/api.php`) on 404. Supports multiple authentication modes: session-based (with CSRF), Bearer token, Token header, and query parameter. Sessions are cached in `PiHoleSessionCache` and automatically refreshed on 401/403.

**StatusItemController** (`StatusItemController.swift`) - Owns the `NSStatusItem` and popover. Left-click toggles blocking directly; right-click opens the popover menu. Uses a custom `StatusItemView` (AppKit) to display the menu bar icon with optional countdown timer overlay.

**ContentView** (`ContentView.swift`) - SwiftUI popover interface with sliding navigation between status and settings views. Contains the main status card, action buttons, duration picker pills, and inline settings form.

### Data Flow

1. `AppDelegate` creates `PiHoleStore` and `StatusItemController` on launch
2. `StatusItemController` observes store's published properties via Combine
3. User actions (click, menu selection) call `PiHoleStore` methods
4. `PiHoleStore` creates ephemeral `PiHoleClient` instances for each request
5. Results update `@Published` properties, triggering UI updates

### API Token Storage

API tokens are stored in the macOS Keychain via `KeychainHelper`. On first launch, tokens migrate from `@AppStorage` (UserDefaults) to Keychain automatically.
