#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CodexQuotaMenubar"
EXECUTABLE_NAME="codex-quota-menubar"
CONFIGURATION="${CONFIGURATION:-release}"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"

cd "$ROOT_DIR"

if [[ ! -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  swift "$ROOT_DIR/scripts/generate-app-icon.swift"
fi

swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
install -m 755 "$ROOT_DIR/.build/$CONFIGURATION/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

echo "Built $APP_DIR"
