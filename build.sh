#!/bin/zsh
# Builds Claude Appshots.
#
#   ./build.sh          rebuild the capture tool and the agent (safe: they
#                       inherit the app's permissions, nothing to re-grant).
#                       Then restart: pkill -f appshot-agent (the app relaunches it).
#   ./build.sh --host   also rebuild the launcher app. Avoid: macOS ties
#                       permissions to its signature, so you must remove and
#                       re-add Claude Appshots in Accessibility and Screen
#                       Recording afterwards.
set -euo pipefail

BASE="$HOME/.claude/appshots"
APP="$HOME/Applications/Claude Appshots.app"
BUNDLE_ID="com.jonathanlewell.claude-appshots"

mkdir -p "$BASE/bin" "$BASE/captures"

echo "Building capture tool…"
swiftc -O -swift-version 5 "$BASE/src/capture/main.swift" -o "$BASE/bin/appshot-capture"
codesign --force --sign - "$BASE/bin/appshot-capture" 2>/dev/null

echo "Building agent…"
swiftc -O -swift-version 5 "$BASE"/src/agent/*.swift -o "$BASE/bin/appshot-agent"
codesign --force --sign - "$BASE/bin/appshot-agent" 2>/dev/null

echo "Building Chrome bridge host…"
swiftc -O -swift-version 5 "$BASE/src/chrome-host/main.swift" -o "$BASE/bin/appshot-chrome-host"
codesign --force --sign - "$BASE/bin/appshot-chrome-host" 2>/dev/null

if [[ "${1:-}" == "--host" || ! -d "$APP" ]]; then
  echo "Building launcher app…"
  mkdir -p "$APP/Contents/MacOS"
  swiftc -O -swift-version 5 "$BASE"/src/host/main.swift -o "$APP/Contents/MacOS/ClaudeAppshots"
  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>Claude Appshots</string>
  <key>CFBundleDisplayName</key><string>Claude Appshots</string>
  <key>CFBundleExecutable</key><string>ClaudeAppshots</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
  echo "Built $APP"
fi
echo "Done."
