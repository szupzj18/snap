#!/usr/bin/env bash
# Builds the Swift package and assembles a signed Snapkit.app.
#
# Usage: scripts/bundle.sh [debug|release]
#
# SIGN_IDENTITY selects the code signing identity. macOS ties the Screen
# Recording permission to the signature, so use a stable identity (for example
# your "Apple Development: ..." certificate) during development; otherwise the
# permission has to be granted again after every rebuild. Defaults to ad-hoc.
set -euo pipefail

CONFIG="${1:-debug}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Snapkit.app"

cd "$ROOT"
# See Makefile: the #Preview macro plugin used by KeyboardShortcuts only ships with Xcode.
unset SDKROOT

# xcodebuild rather than `swift build`: its generated resource accessors look in
# Contents/Resources, while SwiftPM's only check the .app root (which codesign rejects).
case "$CONFIG" in
    release) XC_CONFIG=Release ;;
    *) XC_CONFIG=Debug ;;
esac
xcodebuild -scheme Snapkit -configuration "$XC_CONFIG" -destination 'generic/platform=macOS' \
    -derivedDataPath "$ROOT/build/DerivedData" -quiet build
BIN_DIR="$ROOT/build/DerivedData/Build/Products/$XC_CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Snapkit" "$APP/Contents/MacOS/Snapkit"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# SwiftPM resource bundles (e.g. KeyboardShortcuts localizations).
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP/Contents/Resources/"
done

codesign --force --options runtime --timestamp=none \
    --entitlements "$ROOT/Resources/Snapkit.entitlements" \
    --sign "$SIGN_IDENTITY" "$APP"

echo "Built $APP (signed with: $SIGN_IDENTITY)"
