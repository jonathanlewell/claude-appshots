#!/bin/zsh
# Captures the front window of each running app given (bundle IDs) through the
# installed Claude Appshots.app, so it has the real permissions, and checks the
# result. Deletes the captures afterwards.
#   tests/capture-qa.sh com.google.Chrome com.apple.finder …
set -u
APP="$HOME/Applications/Claude Appshots.app"
TMP=$(mktemp -d)
fail=0
for b in "$@"; do
  out="$TMP/$b.json"
  open -n "$APP" --args --test-capture "$b" "$out"
  for _ in {1..40}; do [[ -s "$out" ]] && break; sleep 0.5; done
  python3 -I - "$out" "$b" <<'PY' || fail=1
import json, os, sys, re
path, b = sys.argv[1], sys.argv[2]
try: d = json.load(open(path))
except Exception as e: print(f"FAIL {b}: no result ({e})"); sys.exit(1)
if d.get("error"): print(f"SKIP {b}: {d['error']}"); sys.exit(0)
probs = []
t = d["text"]
if not (t.startswith("<appshot ") and t.endswith("</appshot>")): probs.append("short block malformed")
if len(t) > 2500: probs.append(f"short block too long ({len(t)})")
for attr in ("app", "bundle-identifier", "window-title", "image", "tree"):
    if f' {attr}="' not in t: probs.append(f"missing {attr}")
tree = d.get("tree", "")
if not os.path.exists(tree): probs.append("tree file missing")
else:
    full = open(tree).read()
    if not (full.startswith("<appshot ") and full.rstrip().endswith("</appshot>")): probs.append("tree file malformed")
    if "\nWindow: " not in full: probs.append("tree has no Window line")
    if re.search(r"secure text field[^\n]*Value: (?!\(hidden\))", full): probs.append("secure field value leaked")
    if oct(os.stat(os.path.dirname(tree)).st_mode & 0o777) != "0o700": probs.append("captures folder not private")
if "screen-recording-not-granted" in d.get("warnings", []): probs.append("no screen recording")
elif not d.get("image") or not os.path.exists(d["image"]): probs.append("screenshot missing")
print(("FAIL " if probs else "ok   ") + f"{b}: nodes={d.get('nodes')} pasted={len(t)} chars" + (" — " + "; ".join(probs) if probs else ""))
for k in ("tree", "image"):
    if d.get(k) and os.path.exists(d[k]): os.remove(d[k])
sys.exit(1 if probs else 0)
PY
done
rm -rf "$TMP"
exit $fail
