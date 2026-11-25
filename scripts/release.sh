#!/bin/bash
set -euo pipefail

# configuration
SCHEME="PiHoleControls"
APP_NAME="PiHoleControls"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/release"
ZIP_NAME="$APP_NAME.zip"

# colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # no color

print_step() {
    echo -e "${GREEN}▶ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✖ $1${NC}"
}

# check we're in the project root
if [ ! -f "$APP_NAME.xcodeproj/project.pbxproj" ]; then
    print_error "run this script from the project root directory"
    exit 1
fi

# get version from project
BUILD_SETTINGS=$(xcodebuild -scheme "$SCHEME" -showBuildSettings)
VERSION=$(awk '/MARKETING_VERSION =/ && !found {print $3; found=1}' <<< "$BUILD_SETTINGS")
if [ -z "$VERSION" ]; then
    print_error "could not determine release version"
    exit 1
fi

# parse arguments
UPLOAD_TO_GITHUB=false
TAG_NAME=""
RELEASE_NOTES=""
DRAFT=false

usage() {
    echo "usage: $0 [options]"
    echo ""
    echo "options:"
    echo "  -u, --upload          upload to github releases"
    echo "  -t, --tag TAG         git tag name (default: v\$VERSION)"
    echo "  -n, --notes NOTES     release notes"
    echo "  -d, --draft           create as draft release"
    echo "  -h, --help            show this help"
    echo ""
    echo "examples:"
    echo "  $0                    build release zip only"
    echo "  $0 -u                 build and upload to github"
    echo "  $0 -u -t v1.0 -n 'first stable release'"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--upload)
            UPLOAD_TO_GITHUB=true
            shift
            ;;
        -t|--tag)
            TAG_NAME="$2"
            shift 2
            ;;
        -n|--notes)
            RELEASE_NOTES="$2"
            shift 2
            ;;
        -d|--draft)
            DRAFT=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# set defaults
if [ -z "$TAG_NAME" ]; then
    TAG_NAME="v$VERSION"
fi

if [ -z "$RELEASE_NOTES" ]; then
    RELEASE_NOTES="Release $TAG_NAME"
fi

if [ "$UPLOAD_TO_GITHUB" = true ]; then
    if [ -n "$(git status --porcelain)" ]; then
        print_error "commit all changes before publishing a release"
        exit 1
    fi
    RELEASE_COMMIT=$(git rev-parse --verify "${TAG_NAME}^{commit}")
    if [ "$RELEASE_COMMIT" != "$(git rev-parse HEAD)" ]; then
        print_error "release tag must point to the current commit"
        exit 1
    fi
fi

echo ""
echo "═══════════════════════════════════════════"
echo "  $APP_NAME release builder"
echo "  version: $VERSION | tag: $TAG_NAME"
echo "═══════════════════════════════════════════"
echo ""

# clean previous build
print_step "cleaning previous build..."
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"
mkdir -p "$BUILD_DIR"

# build archive
print_step "building release archive..."
if ! xcodebuild -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "platform=macOS" \
    archive \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    > "$BUILD_DIR/archive.log" 2>&1; then
    cat "$BUILD_DIR/archive.log"
    print_error "archive failed; see $BUILD_DIR/archive.log"
    exit 1
fi

ARCHIVED_APP=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:ApplicationPath' "$ARCHIVE_PATH/Info.plist")
if [ "$ARCHIVED_APP" != "Applications/$APP_NAME.app" ] || [ ! -d "$ARCHIVE_PATH/Products/$ARCHIVED_APP" ]; then
    print_error "archive does not contain an exportable app"
    exit 1
fi

# Export must succeed; never substitute a possibly incomplete archive product.
print_step "exporting app..."
mkdir -p "$EXPORT_PATH"

# create export options plist for direct distribution
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EOF

if ! xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    > "$BUILD_DIR/export.log" 2>&1; then
    cat "$BUILD_DIR/export.log"
    print_error "export failed; see $BUILD_DIR/export.log"
    exit 1
fi

APP_PATH="$EXPORT_PATH/$APP_NAME.app"
EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Contents/Info.plist")
if [ -z "$EXECUTABLE" ] || [ ! -x "$APP_PATH/Contents/MacOS/$EXECUTABLE" ]; then
    print_error "exported app is missing its executable"
    exit 1
fi
if ! codesign --verify --deep --strict "$APP_PATH"; then
    print_error "exported app signature is invalid"
    exit 1
fi

# create zip
print_step "creating zip archive..."
cd "$EXPORT_PATH"
zip -r -q "$ZIP_NAME" "$APP_NAME.app"
cd - > /dev/null

ZIP_PATH="$EXPORT_PATH/$ZIP_NAME"
ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)

echo ""
print_step "build complete!"
echo "  📦 $ZIP_PATH ($ZIP_SIZE)"
echo ""

# upload to github if requested
if [ "$UPLOAD_TO_GITHUB" = true ]; then
    # check gh cli is installed
    if ! command -v gh &> /dev/null; then
        print_error "github cli (gh) not installed. install with: brew install gh"
        exit 1
    fi

    # check gh is authenticated
    if ! gh auth status &> /dev/null; then
        print_error "not authenticated with github. run: gh auth login"
        exit 1
    fi

    print_step "creating github release $TAG_NAME..."
    
    DRAFT_FLAG=""
    if [ "$DRAFT" = true ]; then
        DRAFT_FLAG="--draft"
    fi

    # create release and upload asset
    gh release create "$TAG_NAME" \
        "$ZIP_PATH" \
        --verify-tag \
        --title "$TAG_NAME" \
        --notes "$RELEASE_NOTES" \
        $DRAFT_FLAG

    echo ""
    print_step "release published!"
    gh release view "$TAG_NAME" --web || echo "  view at: https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)/releases/tag/$TAG_NAME"
else
    echo "to upload to github, run:"
    echo "  $0 --upload"
    echo ""
    echo "or manually:"
    echo "  gh release create $TAG_NAME $ZIP_PATH --title \"$TAG_NAME\" --notes \"$RELEASE_NOTES\""
fi

echo ""
