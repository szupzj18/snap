#!/usr/bin/env bash
# Builds a release Snap.app and packs it into build/Snap-<version>.dmg.
#
# Usage: VERSION=0.2.0 scripts/package.sh
#
# Signing and notarization follow what's available:
#   SIGN_IDENTITY="Developer ID Application: ..."  signs the app and the disk image.
#   NOTARY_PROFILE=<name>  also notarizes and staples the disk image, using credentials saved
#                          with `xcrun notarytool store-credentials <name> ...`.
# Without them the app is ad-hoc signed: it runs, but Gatekeeper asks users to confirm on first
# open (Control-click › Open).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
export VERSION
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
export SIGN_IDENTITY

scripts/bundle.sh release

DMG="$ROOT/build/Snap-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$ROOT/build/Snap.app" "$STAGING/"
# Drag-to-install: the app next to a link to /Applications.
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Snap $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

if [[ "$SIGN_IDENTITY" == "Developer ID Application"* ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
    else
        echo "note: NOTARY_PROFILE not set; the disk image is signed but not notarized" >&2
    fi
else
    echo "note: not signed with a Developer ID; users will have to confirm the first launch" >&2
fi

echo "Packaged $DMG"
