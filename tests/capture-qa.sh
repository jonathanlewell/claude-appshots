#!/bin/zsh
# Checks the newest real Appshot in captures/ (take one with ⌘⌘ first): the
# tree file's format, no password values, a private folder, and a screenshot.
set -u
dir="$HOME/.claude/appshots/captures"
tree=$(ls -t "$dir"/*.txt 2>/dev/null | head -1)
[[ -n "$tree" ]] || { echo "SKIP no captures yet"; exit 0; }
python3 -I - "$tree" <<'PY'
import os, re, sys
tree = sys.argv[1]
full = open(tree).read()
probs = []
if not (full.startswith("<appshot ") and full.rstrip().endswith("</appshot>")): probs.append("tree file malformed")
if "\nWindow: " not in full: probs.append("no Window line")
if re.search(r"secure text field[^\n]*Value: (?!\(hidden\))", full): probs.append("password value leaked")
if os.stat(os.path.dirname(tree)).st_mode & 0o777 != 0o700: probs.append("captures folder not private")
if not os.path.exists(tree[:-4] + ".png"): probs.append("no screenshot")
print(("FAIL " if probs else "ok   ") + os.path.basename(tree) + (" — " + "; ".join(probs) if probs else ""))
sys.exit(1 if probs else 0)
PY
