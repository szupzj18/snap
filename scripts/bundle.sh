#!/usr/bin/env bash
# Builds the Swift package and assembles a signed Snap.app.
#
# Usage: scripts/bundle.sh [debug|release]
#
# SIGN_IDENTITY selects the code signing identity. macOS ties the Screen
# Recording permission to the signature, so use a stable identity (for example
# your "Apple Development: ..." certificate) during development; otherwise the
# permission has to be granted again after every rebuild. Defaults to ad-hoc.
#
# VERSION overrides CFBundleShortVersionString (e.g. 0.2.0 when building a release tag).
# The build number (CFBundleVersion) is the number of commits, so every build counts up.
set -euo pipefail

CONFIG="${1:-debug}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Snap.app"

cd "$ROOT"
# See Makefile: the #Preview macro plugin used by KeyboardShortcuts only ships with Xcode.
unset SDKROOT

# xcodebuild rather than `swift build`: its generated resource accessors look in
# Contents/Resources, while SwiftPM's only check the .app root (which codesign rejects).
case "$CONFIG" in
    release) XC_CONFIG=Release ;;
    *) XC_CONFIG=Debug ;;
esac
xcodebuild -scheme Snap -configuration "$XC_CONFIG" -destination 'generic/platform=macOS' \
    -derivedDataPath "$ROOT/build/DerivedData" -quiet build
BIN_DIR="$ROOT/build/DerivedData/Build/Products/$XC_CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Snap" "$APP/Contents/MacOS/Snap"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# macOS 26 draws app icons from an Icon Composer document compiled into Assets.car, and frames
# old-style .icns icons in a grey tile. Older actool versions can't compile .icon; the app then
# falls back to AppIcon.icns, which is also what macOS 14 and 15 use.
ICON_TMP="$(mktemp -d)"
if xcrun actool "$ROOT/Resources/AppIcon.icon" --compile "$ICON_TMP" --platform macosx \
    --minimum-deployment-target 14.0 --app-icon AppIcon \
    --output-partial-info-plist "$ICON_TMP/partial.plist" >/dev/null 2>&1 \
    && [ -f "$ICON_TMP/Assets.car" ]; then
    cp "$ICON_TMP/Assets.car" "$APP/Contents/Resources/Assets.car"
else
    echo "warning: actool couldn't compile AppIcon.icon (needs Xcode 26); using AppIcon.icns only" >&2
fi
rm -rf "$ICON_TMP"

# SwiftPM resource bundles (e.g. KeyboardShortcuts localizations).
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP/Contents/Resources/"
done

# Notarization requires a secure timestamp; skip the network round trip for other identities.
TIMESTAMP="--timestamp=none"
case "$SIGN_IDENTITY" in
    "Developer ID Application"*) TIMESTAMP="--timestamp" ;;
esac
codesign --force --options runtime $TIMESTAMP \
    --entitlements "$ROOT/Resources/Snap.entitlements" \
    --sign "$SIGN_IDENTITY" "$APP"

echo "Built $APP (signed with: $SIGN_IDENTITY)"
