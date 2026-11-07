#!/bin/zsh
# Runs the self-checks. Add --capture to also capture Chrome, Finder and Claude
# through the installed app (needs its permissions).
cd "${0:A:h}/.."
set -e
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
echo "— hotkey";  cp tests/hotkey-test.swift "$tmp/main.swift"; swiftc -swift-version 5 src/agent/Hotkey.swift "$tmp/main.swift" -o "$tmp/hk" && "$tmp/hk"
echo "— handoff"; cp tests/handoff-test.swift "$tmp/main.swift"; swiftc -swift-version 5 src/agent/Capture.swift "$tmp/main.swift" -o "$tmp/ho" && HOME="$tmp" "$tmp/ho"
echo "— bridge";  node tests/bridge-test.js
echo "— host";    python3 -I tests/host-test.py
if [[ "${1:-}" == "--capture" ]]; then
  echo "— capture"; tests/capture-qa.sh com.google.Chrome com.apple.finder com.anthropic.claudefordesktop
fi
echo "All checks passed."
