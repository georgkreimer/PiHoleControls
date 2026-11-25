# Pi-hole Controls

A macOS menu bar app to control your Pi-hole server. Quickly enable/disable ad blocking with a single click.

## Features

- Toggle Pi-hole blocking from the menu bar
- Timed disable (5, 30, 60 minutes or indefinitely)
- Countdown timer display when blocking is disabled
- Auto-refresh status every 20 seconds
- Supports Pi-hole v5 and v6 APIs
- Self-signed certificate support
- Launch at login
- Runs as a menu bar app (no dock icon by default, configurable)

Timed disables are scheduled on Pi-hole itself. The countdown is a display, not a
client-side re-enable command, so closing the Mac app does not cancel the server timer.

## Installation

Download the latest release from the [Releases](../../releases) page, unzip, and drag `PiHoleControls.app` to your Applications folder.

> **Note**: Since the app is not notarized, macOS will block it on first launch. Right-click the app and select "Open" to bypass Gatekeeper.

## Configuration

1. Right-click the menu bar icon to open the popover, then tap **Settings**
2. Enter your Pi-hole host (e.g., `https://pi.hole` or `http://192.168.1.2:8080`)
3. Enter your API token (found in Pi-hole Admin → Settings → API)
4. Click **Test** to verify

Use HTTPS where possible. HTTP is supported for user-configured LAN/VPN servers,
but does not encrypt credentials at the application layer.

## Building from Source

The macOS app target requires macOS 26.1+. Build with Xcode 26.1 or newer.
The shared `PiHoleKit` package supports macOS 14+ and iOS 17+; that does not lower
the app target's deployment requirement.

The iOS target is currently a scaffold, not a finished companion app. Its dashboard,
server-management UI, and widgets are still pending.

```bash
# clone the repository
git clone https://github.com/georgkreimer/PiHoleControls.git
cd PiHoleControls

# build
xcodebuild -scheme PiHoleControls -destination "platform=macOS" build

# run tests
xcodebuild test -scheme PiHoleControls -destination "platform=macOS"

# shared API, storage, and model tests
swift test --package-path PiHoleKit

# release failure-path tests (no publishing)
python3 scripts/tests/test_release.py

# build the iOS scaffold without device signing
xcodebuild -scheme PiHoleControlsiOS -destination "generic/platform=iOS Simulator" build CODE_SIGNING_ALLOWED=NO
```

## Releasing

A release script is included to build and optionally upload to GitHub Releases.

```bash
# build release zip only
./scripts/release.sh

# build and upload to github releases
# Commit first, then create and push the release tag at that commit.
git tag -a v0.8 -m "PiHoleControls v0.8"
git push origin v0.8
./scripts/release.sh --upload

# with custom tag and notes
./scripts/release.sh -u -t v1.0 -n "first stable release"

# create as draft
./scripts/release.sh -u --draft
```

**Prerequisites**: GitHub CLI (`brew install gh`) and authentication (`gh auth login`).
Uploads require an existing remote release tag; the script never creates a tag on
GitHub's default branch implicitly.
The working tree must be clean and the local tag must identify the current commit.
The release script cleans only its own archive/export output, preserving other
builds under `build/`.
Archive and export must succeed, and the exported executable and signature must
validate before a ZIP is created. Failure logs are retained in `build/archive.log`
and `build/export.log`; the script does not fall back to copying an archive product.

## License

MIT
