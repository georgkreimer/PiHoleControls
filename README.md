# Pi-hole Controls

A macOS menu bar app to control your Pi-hole server. Quickly enable/disable ad blocking with a single click.

## Features

- Toggle Pi-hole blocking from the menu bar
- Timed disable (5, 30, 60 minutes or indefinitely)
- Countdown timer display when blocking is disabled
- Auto-refresh status every 20 seconds
- Supports Pi-hole v5 and v6 APIs
- Self-signed certificate support

## Installation

Download the latest release from the [Releases](../../releases) page, unzip, and drag `PiHoleControls.app` to your Applications folder.

> **Note**: Since the app is not notarized, macOS will block it on first launch. Right-click the app and select "Open" to bypass Gatekeeper.

## Configuration

1. Click the menu bar icon and select **Settings**
2. Enter your Pi-hole host (e.g., `pi.hole` or `192.168.1.2:8080`)
3. Enter your API token (found in Pi-hole Admin → Settings → API)
4. Click **Test connection** to verify

## Building from Source

Requires Xcode 15+ and macOS 14+.

```bash
# clone the repository
git clone https://github.com/YOUR_USERNAME/PiHoleControls.git
cd PiHoleControls

# build
xcodebuild -scheme PiHoleControls -destination "platform=macOS" build

# run tests
xcodebuild test -scheme PiHoleControls -destination "platform=macOS"
```

## Releasing

A release script is included to build and optionally upload to GitHub Releases.

```bash
# build release zip only
./scripts/release.sh

# build and upload to github releases
./scripts/release.sh --upload

# with custom tag and notes
./scripts/release.sh -u -t v1.0 -n "first stable release"

# create as draft
./scripts/release.sh -u --draft
```

**Prerequisites**: GitHub CLI (`brew install gh`) and authentication (`gh auth login`).

## License

MIT
