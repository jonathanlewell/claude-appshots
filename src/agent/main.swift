// appshot-agent: hotkey, capture, paste and menu bar icon.
// Started by "Claude Appshots.app", whose permissions it inherits.
// Safe to rebuild at any time with ~/.claude/appshots/build.sh.
import AppKit

setvbuf(stdout, nil, _IONBF, 0)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.prohibited)
app.run()
