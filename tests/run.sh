#!/bin/zsh
# Runs the self-checks. --installed also checks the installed app's signature
# and the newest real capture.
cd "${0:A:h}/.."
set -e
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
echo "— hotkey";  cp tests/hotkey-test.swift "$tmp/main.swift"; swiftc -swift-version 5 src/agent/Hotkey.swift "$tmp/main.swift" -o "$tmp/hk" && "$tmp/hk"
echo "— handoff"; cp tests/handoff-test.swift "$tmp/main.swift"; swiftc -swift-version 5 src/agent/Capture.swift "$tmp/main.swift" -o "$tmp/ho" && HOME="$tmp" "$tmp/ho"
echo "— paster";  cp tests/paster-test.swift "$tmp/main.swift"; echo 'let signerSHA1 = "0"' > "$tmp/Signer.swift"; swiftc -swift-version 5 ${(@)$(print -l src/agent/*.swift | grep -v '/main.swift$')} src/shared/Signature.swift "$tmp/Signer.swift" "$tmp/main.swift" -o "$tmp/pt" && "$tmp/pt"
echo "— bridge";  node tests/bridge-test.js
echo "— host";    swiftc -O src/chrome-host/main.swift -o "$tmp/appshot-chrome-host" && HOST="$tmp/appshot-chrome-host" python3 -I tests/host-test.py
if [[ "${1:-}" == "--installed" ]]; then
  echo "— signature"; tests/signature-test.sh
  echo "— newest capture"; tests/capture-qa.sh
fi
echo "All checks passed."
