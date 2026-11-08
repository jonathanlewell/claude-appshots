// Self-check for the double-tap detector. Run: tests/run.sh
import AppKit

func log(_ s: String) {}

func flags(_ f: NSEvent.ModifierFlags, at t: TimeInterval) -> NSEvent {
    NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: f, timestamp: t, windowNumber: 0,
                     context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 55)!
}
func key(at t: TimeInterval) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: t, windowNumber: 0,
                     context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
}

func fires(_ events: [NSEvent], _ k: DoubleTapDetector.Key = .command) -> Int {
    var n = 0
    let d = DoubleTapDetector(key: k) { n += 1 }
    events.forEach(d.handle)
    return n
}

let cmd = NSEvent.ModifierFlags.command
let tap = { (t: Double) in [flags(cmd, at: t), flags([], at: t + 0.1)] }
let cases: [(String, [NSEvent], Int)] = [
    ("double tap", tap(0) + tap(0.3), 1),
    ("triple tap fires once", tap(0) + tap(0.3) + tap(0.6), 1),
    ("two double taps", tap(0) + tap(0.3) + tap(2) + tap(2.3), 2),
    ("gap too long", tap(0) + tap(1.0), 0),
    ("held too long", [flags(cmd, at: 0), flags([], at: 0.6)] + tap(0.8), 0),
    ("⌘C in between", tap(0) + [flags(cmd, at: 0.3), key(at: 0.35), flags([], at: 0.4)], 0),
    ("⌘⇧ is not ⌘", tap(0) + [flags([.command, .shift], at: 0.3), flags([], at: 0.4)], 0),
    ("single tap", tap(0), 0),
]
let ctrl = NSEvent.ModifierFlags.control
let ctrlTap = { (t: Double) in [flags(ctrl, at: t), flags([], at: t + 0.1)] }
let fnCtrl = { (t: Double) in [flags(.function, at: t), flags([.function, .control], at: t + 0.05), flags(.function, at: t + 0.1), flags([], at: t + 0.15)] }
let controlCases: [(String, [NSEvent], Int)] = [
    ("⌃⌃ fires", ctrlTap(0) + ctrlTap(0.3), 1),
    ("fn+⌃ twice (Wispr) doesn't", fnCtrl(0) + fnCtrl(0.3), 0),
    ("⌃ then fn+⌃ doesn't", ctrlTap(0) + fnCtrl(0.3), 0),
]
var failed = 0
for (name, events, want) in cases {
    let got = fires(events)
    print((got == want ? "ok   " : "FAIL ") + "\(name): fired \(got), expected \(want)")
    if got != want { failed += 1 }
}
for (name, events, want) in controlCases {
    let got = fires(events, .control)
    print((got == want ? "ok   " : "FAIL ") + "\(name): fired \(got), expected \(want)")
    if got != want { failed += 1 }
}
exit(failed == 0 ? 0 : 1)
