#!/bin/zsh
# Installs or updates Claude Appshots on this Mac. Safe to run again.
#
#   git clone https://github.com/jonathanlewell/claude-appshots.git ~/.claude/appshots && ~/.claude/appshots/install.sh
set -euo pipefail
BASE="$HOME/.claude/appshots"
APP="$HOME/Applications/Claude Appshots.app"
BUNDLE_ID="com.jonathanlewell.claude-appshots"
CERT="Claude Appshots signing"
cd "${0:A:h}"
[[ "$PWD" == "$BASE" ]] || { echo "Clone or move this folder to $BASE first (its paths are fixed)."; exit 1; }
[[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ]] || { echo "Needs macOS 14 or later."; exit 1; }
command -v swiftc >/dev/null || { echo "Needs Apple's command line tools: run  xcode-select --install  then this again."; exit 1; }

echo "1/5 Signing certificate"
if ! security find-certificate -c "$CERT" >/dev/null 2>&1; then
  # This Mac's own certificate, in your login keychain. Its private key can't
  # be exported, and no program may use it without asking you.
  t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
  (umask 077
   /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$t/key.pem" -out "$t/cert.pem" -config /dev/stdin 2>/dev/null <<CNF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$CERT
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF
   pw=$(/usr/bin/openssl rand -hex 16)
   /usr/bin/openssl pkcs12 -export -inkey "$t/key.pem" -in "$t/cert.pem" -out "$t/id.p12" -passout "pass:$pw"
   rm "$t/key.pem"
   security import "$t/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$pw" -x >/dev/null)
  rm -rf "$t"
  echo "   made \"$CERT\" in your login keychain"
fi

echo "2/5 Building (macOS asks for your login password to sign: click Allow, not Always Allow)"
./build.sh
# Restart on the new build.
pkill -f "Claude Appshots.app/Contents/MacOS/" 2>/dev/null || true
if [[ -d "$BASE/bin" ]]; then
  # Earlier versions were signed without a certificate, so macOS's permission
  # entries no longer match. Clear them; macOS asks again on first launch.
  pkill -f "$BASE/bin/appshot-agent" 2>/dev/null || true
  rm -rf "$BASE/bin"
  tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
  tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

echo "3/5 Claude skill and instructions"
mkdir -p "$HOME/.claude/skills"
SKILL="$HOME/.claude/skills/appshot"
# Back up an old copy outside skills/, or Claude would load it as a second skill.
if [[ -e "$SKILL" && ! -L "$SKILL" ]]; then mv "$SKILL" "$HOME/.claude/appshot-skill.backup-$(date +%Y%m%d%H%M%S)"; fi
ln -sfn "$BASE/skill" "$SKILL"
MD="$HOME/.claude/CLAUDE.md"
if ! grep -qs "load the \`appshot\` skill" "$MD"; then
  [[ -s "$MD" ]] && printf '\n' >> "$MD"
  cat claude-md-snippet.md >> "$MD"
  echo "   added the Appshots section to $MD"
fi

echo "4/5 Chrome bridge host"
if [[ -d "/Applications/Google Chrome.app" ]]; then
  ID=$(python3 -I -c "import json,base64,hashlib;k=json.load(open('chrome-extension/manifest.json'))['key'];h=hashlib.sha256(base64.b64decode(k)).hexdigest()[:32];print(''.join(chr(97+int(c,16)) for c in h))")
  DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
  mkdir -p "$DIR"
  cat > "$DIR/com.jonathanlewell.claude_appshots.json" <<JSON
{
  "name": "com.jonathanlewell.claude_appshots",
  "description": "Claude Appshots Chrome bridge",
  "path": "$APP/Contents/MacOS/appshot-chrome-host",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$ID/"]
}
JSON
else
  echo "   Chrome isn't installed; skipping"
fi

echo "5/5 Starting Claude Appshots"
open "$APP"

cat <<EOF

Done. If macOS asks, allow Claude Appshots under System Settings → Privacy &
Security → Accessibility, and under Screen & System Audio Recording (menu bar
icon → Permissions… opens the right pane). Updates keep these.

Chrome, once (to let Claude control the exact tab you capture):
chrome://extensions → Developer mode on → Load unpacked → $BASE/chrome-extension
After an update, click reload on Claude Appshots bridge there.

Then open a Claude Code session, go to any window and double-tap ⌃ Control.
EOF
