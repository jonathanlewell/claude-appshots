# Self-check for the Chrome bridge's native host. Run: tests/run.sh
import json, os, struct, subprocess, sys, tempfile, time
host = os.path.join(os.path.dirname(__file__), "..", "bin", "appshot-chrome-host")
home = tempfile.mkdtemp()
os.makedirs(f"{home}/.claude/appshots")
pending = f"{home}/.claude/appshots/chrome-pending.json"
def call(msg):
    b = json.dumps(msg).encode()
    out = subprocess.run([host], input=struct.pack("<I", len(b)) + b, capture_output=True, env={"HOME": home}).stdout
    return json.loads(out[4:4 + struct.unpack("<I", out[:4])[0]])
failed = 0
def check(name, ok):
    global failed
    print(("ok   " if ok else "FAIL ") + name); failed += not ok
now = time.time()
check("empty queue", call({"cmd": "pending"}) == {"captures": []})
json.dump({"captures": [{"time": now - 1000, "url": "old"}, {"time": now - 5, "url": "a"}, {"time": now, "url": "b"}]}, open(pending, "w"))
urls = [c["url"] for c in call({"cmd": "pending"})["captures"]]
check("drops captures older than 15 minutes", urls == ["a", "b"])
call({"cmd": "done", "times": [now - 5]})
check("done removes only those", [c["url"] for c in call({"cmd": "pending"})["captures"]] == ["b"])
call({"cmd": "done", "times": [now]})
check("last one done deletes the file", not os.path.exists(pending))
check("unknown command is refused", "error" in call({"cmd": "rm -rf"}))
sys.exit(1 if failed else 0)
