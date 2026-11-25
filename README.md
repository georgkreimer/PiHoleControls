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

## Parked Temporary-Allowlist Branch

New temporary exceptions are disabled until a server-side expiry mechanism exists.
The app cannot guarantee deletion while it is crashed, closed, or offline.

Existing entries remain visible under **Pending allowlist cleanup**, including
expired entries. Old records did not capture server or ownership information, so
they require explicit confirmation on the original server. Verify that the domain
was not permanently allowed before confirming removal.

Confirmed removals are journaled atomically under Application Support/PiHoleControls
before any DELETE request. Failed removals remain pending and retry every 30 seconds
while the app is running with the original server selected. Missing or corrupt
records are not silently overwritten. No credentials are stored in the journal.

Recently blocked queries require Pi-hole query logging. The fallback API has no
timestamps, so the UI displays "Time unknown" rather than inventing a block time.

## Installation

Download the latest release from the [Releases](../../releases) page, unzip, and drag `PiHoleControls.app` to your Applications folder.

> **Note**: Since the app is not notarized, macOS will block it on first launch. Right-click the app and select "Open" to bypass Gatekeeper.

## Configuration

1. Right-click the menu bar icon to open the popover, then tap **Settings**
2. Enter your Pi-hole host (e.g., `https://pi.hole` or `http://192.168.1.2:8080`)
3. Enter your API token (found in Pi-hole Admin → Settings → API)
4. Click **Test** to verify

## Building from Source

Requires Xcode 26.1+ and macOS 26.1+.

```bash
# clone the repository
git clone https://github.com/georgkreimer/PiHoleControls.git
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
