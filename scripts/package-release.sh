#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CodexQuotaMenubar"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
RELEASE_DIR="$ROOT_DIR/release"
DMG_STAGING="$ROOT_DIR/.build/dmg-staging"

"$ROOT_DIR/scripts/build-app.sh"

rm -rf "$RELEASE_DIR" "$DMG_STAGING"
mkdir -p "$RELEASE_DIR" "$DMG_STAGING"

ditto -c -k --keepParent "$APP_DIR" "$RELEASE_DIR/$APP_NAME-macOS.zip"

cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create \
  -volname "Codex Quota Menubar" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$RELEASE_DIR/$APP_NAME-macOS.dmg"

shasum -a 256 "$RELEASE_DIR"/* > "$RELEASE_DIR/checksums.txt"
echo "Packaged release artifacts in $RELEASE_DIR"
