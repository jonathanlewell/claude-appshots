#!/bin/zsh
# Checks the installed app passes its own signature check, and that a copy
# with one helper swapped, or re-signed without this Mac's certificate, fails.
set -eu
APP="$HOME/Applications/Claude Appshots.app"
SHA=$(security find-certificate -c "Claude Appshots signing" -Z | awk '/SHA-1/ {print $NF}')
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
echo "let signerSHA1 = \"${SHA:l}\"" > "$t/Signer.swift"
echo 'import Foundation; print(bundleIntact(URL(fileURLWithPath: CommandLine.arguments[1])))' > "$t/main.swift"
swiftc "${0:A:h}/../src/shared/Signature.swift" "$t/Signer.swift" "$t/main.swift" -o "$t/check"
failed=0
check() { [[ "$($t/check "$2")" == "$3" ]] && echo "ok   $1" || { echo "FAIL $1"; failed=1; } }
check "installed app is intact" "$APP" true
ditto "$APP" "$t/swapped.app"; cp /usr/bin/true "$t/swapped.app/Contents/MacOS/appshot-capture"
check "a swapped helper is refused" "$t/swapped.app" false
ditto "$APP" "$t/resigned.app"; cp /usr/bin/true "$t/resigned.app/Contents/MacOS/appshot-capture"
codesign -f -s - "$t/resigned.app/Contents/MacOS/appshot-capture" 2>/dev/null
codesign -f -s - --identifier com.jonathanlewell.claude-appshots "$t/resigned.app" 2>/dev/null
check "a copy re-signed without the certificate is refused" "$t/resigned.app" false
exit $failed
