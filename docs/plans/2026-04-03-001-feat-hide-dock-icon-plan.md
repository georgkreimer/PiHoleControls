---
title: "feat: Hide dock icon for menu bar app"
type: feat
status: active
date: 2026-04-03
---

# feat: Hide dock icon for menu bar app

## Enhancement Summary

**Deepened on:** 2026-04-03
**Agents used:** Explore (setActivationPolicy research), Best Practices Researcher, Architecture Strategist, Code Simplicity Reviewer

### Key Improvements Over Initial Plan
1. Hybrid approach: `LSUIElement = YES` in build settings + programmatic `setActivationPolicy` (prevents dock icon flash on launch)
2. Removed `PiHoleStore` dependency — `showDockIcon` is app presentation, not Pi-hole domain state
3. Eliminated Combine — SwiftUI `.onChange(of:)` is sufficient
4. Single toggle location (popover settings only) — avoids duplication
5. Added activation workaround for `.accessory` → `.regular` transition

## Overview

PiHoleControls is a menu bar-only app, but it currently shows a dock icon because there is no `LSUIElement` setting or `setActivationPolicy(.accessory)` call. The dock icon serves no purpose — all interaction happens through the status bar item and its popover.

This plan hides the dock icon by default, with a user preference to show it.

## Problem Statement

The app shows a dock icon that:
- Clutters the dock for a utility that has no main window
- Doesn't do anything when clicked (no main window to show)
- Is inconsistent with other menu bar utilities (Bartender, iStat Menus, Ice, etc.)

## Proposed Solution: Hybrid Approach

Use **both** `LSUIElement = YES` (static plist) **and** `NSApp.setActivationPolicy` (programmatic):

1. `LSUIElement = YES` in build settings — suppresses dock icon from the very first frame (no flash)
2. `setActivationPolicy(.regular)` at launch **only if** the user preference says to show the dock icon
3. `.onChange(of:)` in SwiftUI to toggle at runtime

This is the pattern used by Cork, Ice, and other popular macOS menu bar apps.

**Why hybrid over programmatic-only:** Without `LSUIElement`, the dock icon briefly appears for one frame during launch before `applicationDidFinishLaunching` runs. `LSUIElement` prevents this flash entirely.

## Acceptance Criteria

- [ ] Dock icon is hidden by default on fresh install (no flash)
- [ ] Popover settings has a toggle: "Show dock icon"
- [ ] Toggling the preference takes effect immediately (no restart)
- [ ] Preference persists across app launches via `@AppStorage`
- [ ] When dock icon is hidden, app is not in Cmd+Tab or Dock
- [ ] When dock icon is shown, Settings window is accessible via app menu
- [ ] Status bar item and popover work correctly in both modes

## Implementation

### Files to change

| File | Change |
|------|--------|
| `PiHoleControls.xcodeproj/project.pbxproj` | Add `INFOPLIST_KEY_LSUIElement = YES` to Debug and Release |
| `PiHoleControls/PiHoleControlsApp.swift` | Read preference at launch, apply activation policy |
| `PiHoleControls/ContentView.swift` | Add "Show dock icon" toggle in `SettingsContentView` |

**Not changed:** `PiHoleStore.swift` — this is app presentation, not Pi-hole domain state.

### Build Settings (project.pbxproj)

Add to both Debug and Release build configurations:

```
INFOPLIST_KEY_LSUIElement = YES;
```

This ensures the dock icon is hidden from the first frame, before any code runs.

### PiHoleControlsApp.swift

Read the preference at launch and apply. No Combine needed.

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = PiHoleStore()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply dock icon preference BEFORE creating UI.
        // LSUIElement=YES already hides it; only act if user wants it shown.
        if UserDefaults.standard.bool(forKey: "showDockIcon") {
            NSApp.setActivationPolicy(.regular)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        statusItemController = StatusItemController(store: store)
        store.refreshStatus()
        store.startAutoRefresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stopAutoRefresh()
    }
}
```

### ContentView.swift (SettingsContentView)

Add a toggle with `@AppStorage` + `.onChange`. The `@AppStorage` binding handles persistence; `.onChange` applies the policy at runtime.

```swift
@AppStorage("showDockIcon") private var showDockIcon = false

// In the settings card, after the self-signed cert toggle:
Toggle(isOn: $showDockIcon) {
    HStack(spacing: 8) {
        Image(systemName: "dock.rectangle")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        Text("Show dock icon")
            .font(.system(size: 12, weight: .medium, design: .rounded))
    }
}
.toggleStyle(.switch)
.controlSize(.mini)
.onChange(of: showDockIcon) {
    NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    if showDockIcon {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
```

**Why only in the popover, not SettingsView.swift:** The popover is always one click away. The standalone Settings window is secondary and only accessible when the dock icon is already visible. Adding the toggle to both would compound the existing UI duplication issue.

## Edge Cases

### Research Insights

**Switching `.accessory` → `.regular` (showing dock icon):**
- The app menu bar may appear but be unclickable without `NSApp.activate`. The 100ms delay + activate call handles this.
- Source: Peter Steinberger's "Showing Settings from macOS Menu Bar Items: A 5-Hour Journey"

**Switching `.regular` → `.accessory` (hiding dock icon):**
- macOS will hide all visible windows. The popover is attached to the status item (not a window), so it survives. The standalone Settings window would close — acceptable behavior.
- Source: onmyway133/notes #569

**Settings scene accessibility:**
- In `.accessory` mode, the `Settings` scene (Cmd+,) is unreachable because there's no app menu. This is fine — settings are always available through the popover.
- The `Settings` scene still works when the user switches back to `.regular` mode.
- No hidden-window workaround needed (that's only needed for `SettingsLink` from `MenuBarExtra`).

**Status bar item tooltips:**
- Toggling activation policy can kill status item tooltips. The app uses a custom `StatusItemView`, which is not affected.

**First launch:**
- `UserDefaults.standard.bool(forKey: "showDockIcon")` returns `false` (default). Combined with `LSUIElement = YES`, the dock icon stays hidden. Consistent behavior.

## Sources

- [Showing Settings from macOS Menu Bar Items: A 5-Hour Journey — Peter Steinberger](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items)
- [Swift Protip: Hiding Your App's Icon From the Dock Properly — David Bures (Cork)](https://buresdv.substack.com/p/swift-protip-hiding-your-apps-icon)
- [NSApp.setActivationPolicy API Documentation — Apple](https://developer.apple.com/documentation/appkit/nsapplication/setactivationpolicy(_:))
- [NSApp.setActivationPolicy(.accessory) hides all windows — onmyway133](https://github.com/onmyway133/notes/issues/569)
- [SettingsAccess Library — orchetect](https://github.com/orchetect/SettingsAccess) (not needed for this implementation)
- [Workaround for Unclickable App Menu Bug — Aral Balkan](https://ar.al/2018/09/17/workaround-for-unclickable-app-menu-bug-with-window.makekeyandorderfront-and-nsapp.activate-on-macos/)
- Existing pattern: `@AppStorage("allowSelfSignedCert")` toggle in `ContentView.swift`
