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
exit(failed == 0 ? 0 : 1)
