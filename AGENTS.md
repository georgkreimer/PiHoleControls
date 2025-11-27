# Repository Guidelines

These notes keep contributions consistent for the Pi-hole macOS menu bar controller. Favor small, focused changes and update this guide if the workflow shifts.

## Project Structure & Module Organization
- `PiHoleControls/`: SwiftUI app sources (`ContentView`, `SettingsView`, `PiHoleStore`, `PiHoleClient`, `PiHoleControlsApp`) plus `Assets.xcassets`.
- `PiHoleControlsTests/`: Unit tests using the new `Testing` framework.
- `PiHoleControlsUITests/`: XCTest UI and launch performance tests.
- `PiHoleControls.xcodeproj`: Xcode project; no Swift Package manifest.
- State is centralized in `PiHoleStore` (`@MainActor`, `@AppStorage`), while `PiHoleClient` encapsulates Pi-hole API calls.

## Build, Test, and Development Commands
- Build (macOS target): `xcodebuild -scheme PiHoleControls -destination "platform=macOS" build`
- Unit tests: `xcodebuild test -scheme PiHoleControls -destination "platform=macOS" -only-testing:PiHoleControlsTests`
- UI tests: `xcodebuild test -scheme PiHoleControls -destination "platform=macOS" -only-testing:PiHoleControlsUITests`
- Xcode workflow: open `PiHoleControls.xcodeproj`, use the PiHoleControls scheme, and run on “My Mac” for the menu bar host app.

## Coding Style & Naming Conventions
- Swift 5.9+ with SwiftUI and async/await; default Xcode 4-space indentation.
- Prefer `struct` views, `ObservableObject`/`@Published` for state, `@MainActor` for UI-bound stores, and `Task {}` for async actions.
- Network work lives in `PiHoleClient`; avoid duplicating request building—extend it instead.
- Name async methods with verbs (`refreshStatus`, `enableBlocking`), and keep error strings user-friendly (shown in the menu UI).

## Testing Guidelines
- Unit tests: `Testing` macros (`@Test`) in `PiHoleControlsTests`; name tests by intent (`fetchStatus_returnsEnabled`).
- UI tests: XCTest in `PiHoleControlsUITests`; keep launch performance test intact and add flows for toggling blocking and reading status.
- Aim for coverage on `PiHoleClient` edge cases (bad URL, 4xx/5xx, self-signed cert toggle) and `PiHoleStore` state transitions.

## Commit & Pull Request Guidelines
- Commits: short, imperative summaries (e.g., “Add Pi-hole status fetch”)—current history only has “Initial Commit.”
- PRs: include a one-paragraph summary, test command output, screenshots/gifs for UI changes (menu bar and settings), and note Pi-hole version used for manual verification.

## Security & Configuration Tips
- Do not commit real Pi-hole hosts or API tokens; values are stored via `@AppStorage` in user defaults.
- When using self-signed certificates, ensure the toggle (`allowSelfSignedCert`) is deliberate and scoped to Pi-hole only; never reuse that delegate elsewhere.
- Avoid adding logging that could expose tokens or URLs; prefer user-facing error strings already shown in `ContentView`.
