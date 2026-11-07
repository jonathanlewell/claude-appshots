#!/bin/zsh
# Installs Claude Appshots on this Mac. Safe to run again: it only adds what's
# missing and never rebuilds the app (which would reset its permissions).
#
#   git clone <your repo> ~/.claude/appshots && ~/.claude/appshots/install.sh
set -euo pipefail
BASE="$HOME/.claude/appshots"
cd "${0:A:h}"
[[ "$PWD" == "$BASE" ]] || { echo "Clone or move this folder to $BASE first (its paths are fixed)."; exit 1; }
[[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ]] || { echo "Needs macOS 14 or later."; exit 1; }
command -v swiftc >/dev/null || { echo "Needs Apple's command line tools: run  xcode-select --install  then this again."; exit 1; }

echo "1/4 Building"
./build.sh >/dev/null
pkill -f "$BASE/bin/appshot-agent" 2>/dev/null || true  # the app restarts it on the new build

echo "2/4 Claude skill and instructions"
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

echo "3/4 Chrome bridge host"
if [[ -d "/Applications/Google Chrome.app" ]]; then
  ID=$(python3 -I -c "import json,base64,hashlib;k=json.load(open('chrome-extension/manifest.json'))['key'];h=hashlib.sha256(base64.b64decode(k)).hexdigest()[:32];print(''.join(chr(97+int(c,16)) for c in h))")
  DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
  mkdir -p "$DIR"
  cat > "$DIR/com.jonathanlewell.claude_appshots.json" <<JSON
{
  "name": "com.jonathanlewell.claude_appshots",
  "description": "Claude Appshots Chrome bridge",
  "path": "$BASE/bin/appshot-chrome-host",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$ID/"]
}
JSON
else
  echo "   Chrome isn't installed; skipping"
fi

echo "4/4 Starting Claude Appshots"
open "$HOME/Applications/Claude Appshots.app"

cat <<EOF

Done. Two things only you can do:

1. Permissions: allow Claude Appshots under System Settings → Privacy & Security →
   Accessibility, and under Screen & System Audio Recording. (It asks on first run;
   the menu bar icon → Permissions… opens the right pane.)
2. Chrome (to let Claude control the exact tab you capture): chrome://extensions →
   Developer mode on → Load unpacked → $BASE/chrome-extension

Then open a Claude Code session, go to any window and double-tap ⌘.
EOF
