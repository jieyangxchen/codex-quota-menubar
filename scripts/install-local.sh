#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CodexQuotaMenubar"
EXECUTABLE_NAME="codex-quota-menubar"
BUNDLE_ID="io.github.jieyangxchen.codex-quota-menubar"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/$BUNDLE_ID.plist"
SERVICE_TARGET="gui/$(id -u)/$BUNDLE_ID"
EXECUTABLE_PATH="$INSTALLED_APP/Contents/MacOS/$EXECUTABLE_NAME"

xml_escape() {
  sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&apos;/g"
}

"$ROOT_DIR/scripts/build-app.sh"

mkdir -p "$INSTALL_DIR" "$PLIST_DIR"
rm -rf "$INSTALLED_APP"
ditto "$ROOT_DIR/dist/$APP_NAME.app" "$INSTALLED_APP"

escaped_executable="$(printf '%s' "$EXECUTABLE_PATH" | xml_escape)"
cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$BUNDLE_ID</string>
    <key>ProgramArguments</key>
    <array>
        <string>$escaped_executable</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>/tmp/codex-quota-menubar.out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/codex-quota-menubar.err.log</string>
</dict>
</plist>
PLIST

plutil -lint "$PLIST_PATH" >/dev/null
launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl kickstart -k "$SERVICE_TARGET"

echo "Installed $INSTALLED_APP"
echo "Loaded $PLIST_PATH"
