#!/bin/bash
#
# Builds a Release SelfCam.app and packages it as a drag-to-install DMG.
#
# Output: dist/SelfCam-<version>.dmg
#
# This is the FREE / ad-hoc flow: the app is signed with whatever identity Xcode
# resolves automatically (your Personal Team), but it is NOT notarized. You can run
# it on your own Mac with no warning; friends who download it must right-click ->
# Open once to get past Gatekeeper (see RELEASING.md). The hooks for adding
# Developer ID signing + notarization later are noted at the bottom.

set -euo pipefail

cd "$(dirname "$0")/.."   # repo root

SCHEME="SelfCam"
CONFIG="Release"
APP_NAME="SelfCam"
# Build OUTSIDE the repo. If the project lives in an iCloud-synced folder
# (Desktop / Documents), the file provider stamps extended attributes onto the
# build output that codesign rejects ("resource fork, Finder information, or
# similar detritus not allowed"). TMPDIR is local and unsynced.
BUILD_DIR="${TMPDIR%/}/SelfCam-build"
DIST_DIR="$(pwd)/dist"

# Xcode is required; honor an existing DEVELOPER_DIR, otherwise default to Xcode.app
# (xcodebuild fails if xcode-select points at the Command Line Tools).
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "==> Building $SCHEME ($CONFIG)…"
rm -rf "$BUILD_DIR"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$SCHEME" -configuration "$CONFIG" \
  -derivedDataPath "$BUILD_DIR" -destination "platform=macOS" \
  build | tail -1

APP="$BUILD_DIR/Build/Products/$CONFIG/$APP_NAME.app"
[ -d "$APP" ] || { echo "Build did not produce $APP" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"

echo "==> Packaging $DMG…"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"   # drag-to-install target
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "==> Done: $DMG"

# ---------------------------------------------------------------------------
# To upgrade to notarized distribution (no Gatekeeper warning for anyone) later:
#   1. Join the Apple Developer Program and create a "Developer ID Application" cert.
#   2. codesign --force --options runtime --sign "Developer ID Application: …" "$APP"
#      (Hardened Runtime is already enabled in the project.)
#   3. xcrun notarytool submit "$DMG" --keychain-profile "<profile>" --wait
#   4. xcrun stapler staple "$DMG"
# ---------------------------------------------------------------------------
