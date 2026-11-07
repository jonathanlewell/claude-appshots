#!/bin/zsh
# Installs the Claude Appshots Chrome bridge, which lets Claude control the
# exact Chrome tab you capture (instead of you adding it to Claude's group).
#
# 1. Registers the native host with Chrome (one small JSON file).
# 2. Opens chrome://extensions so you can load the extension:
#    turn on Developer mode → Load unpacked → choose
#    ~/.claude/appshots/chrome-extension
#
# To remove: delete the extension in chrome://extensions, then
#   rm ~/Library/Application\ Support/Google/Chrome/NativeMessagingHosts/com.jonathanlewell.claude_appshots.json
set -euo pipefail
BASE="$HOME/.claude/appshots"
ID=$(cat "$BASE/keys/extension-id.txt")
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
echo "Registered the native host for extension $ID."
echo "Now in Chrome: go to chrome://extensions → Developer mode on → Load unpacked → $BASE/chrome-extension"
open -a "Google Chrome" "chrome://extensions"
