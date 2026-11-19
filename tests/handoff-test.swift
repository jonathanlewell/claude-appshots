// Self-check for the agent's Chrome capture notes. Run: tests/run.sh (with HOME set to a temp folder)
import Foundation

func capture(_ url: String, _ bundle: String = "com.google.Chrome") -> CaptureResult {
    CaptureResult(text: "", image: nil, app: "Google Chrome", bundleID: bundle, windowTitle: url + " - Google Chrome", url: url, warnings: [])
}
func urls() -> [String] {
    guard let d = try? Data(contentsOf: ChromeHandoff.file),
          let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [] }
    return ((o["captures"] as? [[String: Any]]) ?? []).compactMap { $0["url"] as? String }
}
try? FileManager.default.createDirectory(at: Paths.base, withIntermediateDirectories: true)
var failed = 0
func check(_ name: String, _ ok: Bool) { print((ok ? "ok   " : "FAIL ") + name); if !ok { failed += 1 } }

ChromeHandoff.record(capture("a.example"))
ChromeHandoff.record(capture("b.example"))
check("keeps several captures", urls() == ["a.example", "b.example"])
ChromeHandoff.record(capture("a.example"))
check("a repeat replaces the older note", urls() == ["b.example", "a.example"])
ChromeHandoff.record(capture("finder", "com.apple.finder"))
check("ignores other apps", urls() == ["b.example", "a.example"])
let old = try! JSONSerialization.data(withJSONObject: ["captures": [["time": Date().timeIntervalSince1970 - 3600, "url": "stale"]]])
try! old.write(to: ChromeHandoff.file)
ChromeHandoff.record(capture("c.example"))
check("drops notes older than 15 minutes", urls() == ["c.example"])
let perms = (try? FileManager.default.attributesOfItem(atPath: ChromeHandoff.file.path)[.posixPermissions] as? Int) ?? 0
check("note is private", perms == 0o600)

// Which profile a capture came from, and whether the bridge is installed there.
check("profile from title", ChromeBridge.profileName(fromTitle: "Manage products - Google Chrome – Bibiji · Claude") == "Bibiji · Claude")
check("no profile in a one-profile title", ChromeBridge.profileName(fromTitle: "Inbox - Google Chrome") == nil)
check("page title mentioning Chrome", ChromeBridge.profileName(fromTitle: "Google Chrome tips - Google Chrome – Work") == "Work")
let chrome = Paths.chrome
func writeJSON(_ o: Any, _ path: String) {
    let u = chrome.appendingPathComponent(path)
    try! FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! JSONSerialization.data(withJSONObject: o).write(to: u)
}
let bridge = ["extensions": ["settings": [ChromeBridge.extensionID: ["path": "/x", "location": 4]]]]
writeJSON(["profile": ["last_used": "Default", "info_cache": ["Default": ["name": "Home"], "Profile 30": ["name": "Bibiji · Claude"], "Profile 31": ["name": "Off"]]]], "Local State")
writeJSON(bridge, "Default/Preferences")
writeJSON(["extensions": ["settings": ["someotherextensionid": [:]]]], "Profile 30/Preferences")
writeJSON(["extensions": ["settings": [ChromeBridge.extensionID: ["path": "/x", "disable_reasons": [1]]]]], "Profile 31/Preferences")
check("bridge found in its profile", ChromeBridge.status(windowTitle: "A - Google Chrome – Home") == .init(profileName: "Home", profileDir: "Default", installed: true))
check("bridge missing in another profile", ChromeBridge.status(windowTitle: "A - Google Chrome – Bibiji · Claude") == .init(profileName: "Bibiji · Claude", profileDir: "Profile 30", installed: false))
check("switched-off bridge counts as missing", ChromeBridge.status(windowTitle: "A - Google Chrome – Off")?.installed == false)
check("unknown profile isn't guessed", ChromeBridge.status(windowTitle: "A - Google Chrome – Nobody") == nil)
check("no name with several profiles isn't guessed", ChromeBridge.status(windowTitle: "A - Google Chrome") == nil)
let flagged = CaptureResult(text: "<appshot app=\"Google Chrome\" url=\"x\">\nFocused: y\n</appshot>", image: nil, app: "", bundleID: "", windowTitle: "", url: nil, warnings: [])
    .adding(attribute: "chrome-bridge-missing-in-profile", "A \"B\" & <C>")
check("flag goes on the appshot tag, escaped", flagged.text.hasPrefix("<appshot chrome-bridge-missing-in-profile=\"A &quot;B&quot; &amp; &lt;C&gt;\" app=\"Google Chrome\""))
check("stamp from the tree file name", CaptureRunner.stamp(fromPath: "/x/captures/Google Chrome Appshot 2026-11-19T06-44-40.415Z.txt") == "2026-11-19T06-44-40.415Z")
var stamped = capture("e.example"); stamped.stamp = "2026-11-19T06-44-40.415Z"
ChromeHandoff.record(stamped)
let notes = ((try? JSONSerialization.jsonObject(with: Data(contentsOf: ChromeHandoff.file))) as? [String: Any])?["captures"] as? [[String: Any]] ?? []
check("note carries the stamp", notes.contains { ($0["stamp"] as? String) == "2026-11-19T06-44-40.415Z" && ($0["url"] as? String) == "e.example" })
check("record reports a missing bridge", ChromeHandoff.record(CaptureResult(text: "", image: nil, app: "Google Chrome", bundleID: "com.google.Chrome", windowTitle: "d.example - Google Chrome – Bibiji · Claude", url: "d.example", warnings: []))?.installed == false)
exit(failed == 0 ? 0 : 1)
