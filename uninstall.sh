#!/bin/zsh
# Removes everything install.sh added except this folder and the Chrome
# extension (remove that in chrome://extensions). Captures are deleted.
set -u
osascript -e 'quit app "Claude Appshots"' 2>/dev/null
pkill -f "Claude Appshots.app/Contents/MacOS/ClaudeAppshots" 2>/dev/null
rm -rf "$HOME/Applications/Claude Appshots.app" "$HOME/.claude/appshots/captures" "$HOME/.claude/appshots/bin"
[[ -L "$HOME/.claude/skills/appshot" ]] && rm "$HOME/.claude/skills/appshot"
rm -f "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.jonathanlewell.claude_appshots.json"
tccutil reset Accessibility com.jonathanlewell.claude-appshots >/dev/null 2>&1
tccutil reset ScreenCapture com.jonathanlewell.claude-appshots >/dev/null 2>&1
echo "Removed. Delete the Appshots section from ~/.claude/CLAUDE.md, the Chrome extension, and this folder if you want them gone too."
