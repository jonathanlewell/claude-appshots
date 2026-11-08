#!/bin/zsh
# Builds ~/Applications/Claude Appshots.app with every helper inside it, and
# signs it with this Mac's own "Claude Appshots signing" certificate (install.sh
# makes it). macOS ties the Accessibility and Screen Recording permissions to
# that certificate, so rebuilding keeps them.
#
# macOS asks for your login password once per build to use the certificate.
# Click Allow, not Always Allow: that prompt is what stops anything else from
# signing a look-alike that would get Appshots' permissions.
#
# Run install.sh rather than this directly: it also restarts the app.
set -euo pipefail

BASE="$HOME/.claude/appshots"
APP="$HOME/Applications/Claude Appshots.app"
BUNDLE_ID="com.jonathanlewell.claude-appshots"
CERT="Claude Appshots signing"
cd "$BASE"

SHA=$(security find-certificate -c "$CERT" -Z 2>/dev/null | awk '/SHA-1/ {print $NF}')
[[ -n "$SHA" ]] || { echo "No \"$CERT\" certificate; run install.sh."; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
echo "let signerSHA1 = \"${SHA:l}\"" > "$tmp/Signer.swift"

# Built and signed beside the old app, which is replaced only on success.
NEW="$tmp/Claude Appshots.app"
MACOS="$NEW/Contents/MacOS"
mkdir -p "$MACOS" "$BASE/captures"
build() { swiftc -O -swift-version 5 "${@:2}" -o "$tmp/$1"; }

echo "Building…"
build ClaudeAppshots src/host/main.swift src/shared/Signature.swift "$tmp/Signer.swift"
build appshot-agent src/agent/*.swift src/shared/Signature.swift "$tmp/Signer.swift"
build appshot-capture src/capture/main.swift
build appshot-chrome-host src/chrome-host/main.swift
for b in ClaudeAppshots appshot-agent appshot-capture appshot-chrome-host; do mv -f "$tmp/$b" "$MACOS/$b"; done

cat > "$NEW/Contents/Info.plist" <<PLIST
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

# Helpers are sealed into the app's signature; hardened runtime stops code
# being injected into any of them.
for h in appshot-agent appshot-capture appshot-chrome-host; do
  codesign --force --options runtime --identifier "$BUNDLE_ID.${h#appshot-}" --sign - "$MACOS/$h" 2>/dev/null
done
echo "Signing (macOS asks for your login password: click Allow)…"
codesign --force --options runtime --identifier "$BUNDLE_ID" --sign "$SHA" "$NEW"
codesign --verify --strict --deep -R="certificate leaf = H\"${SHA:l}\"" "$NEW"
mkdir -p "${APP:h}"; rm -rf "$APP"; mv "$NEW" "$APP"
echo "Built $APP"
