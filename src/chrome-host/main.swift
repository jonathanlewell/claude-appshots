// appshot-chrome-host: Chrome native messaging host for the Claude Appshots
// Chrome bridge extension. Chrome starts it once per request.
//
// Requests (JSON, length-prefixed as Chrome's native messaging requires):
//   {"cmd":"pending"}             → {"captures":[{"url":…,"windowTitle":…,"time":…}, …]}
//   {"cmd":"done","times":[<t>]}  → marks those captures as handled
//   {"cmd":"log","msg":"…"}      → appends a line to appshots.log
//
// The note it reads is written by the Appshots agent after each Chrome capture
// (~/.claude/appshots/chrome-pending.json) and is valid for 15 minutes.
import Foundation

let home = ProcessInfo.processInfo.environment["HOME"].map { URL(fileURLWithPath: $0) }
    ?? FileManager.default.homeDirectoryForCurrentUser
let base = home.appendingPathComponent(".claude/appshots")
let pendingFile = base.appendingPathComponent("chrome-pending.json")
let logFile = base.appendingPathComponent("appshots.log")
let maxAge: TimeInterval = 15 * 60

func log(_ s: String) {
    let f = ISO8601DateFormatter()
    // One line per event, whatever the extension sends.
    let line = "\(f.string(from: Date())) chrome-bridge: \(s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " "))\n"
    if let h = try? FileHandle(forWritingTo: logFile) {
        h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
    }
}

func readMessage() -> [String: Any]? {
    let stdin = FileHandle.standardInput
    let lenData = stdin.readData(ofLength: 4)
    guard lenData.count == 4 else { return nil }
    let len = lenData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    guard len > 0, len < 1_000_000 else { return nil }
    let body = stdin.readData(ofLength: Int(len))
    return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
}

func reply(_ obj: [String: Any]) {
    guard let d = try? JSONSerialization.data(withJSONObject: obj) else { return }
    var len = UInt32(d.count)
    let out = FileHandle.standardOutput
    out.write(Data(bytes: &len, count: 4))
    out.write(d)
}

func readList() -> [[String: Any]] {
    guard let d = try? Data(contentsOf: pendingFile),
          let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
          let l = o["captures"] as? [[String: Any]] else { return [] }
    let now = Date().timeIntervalSince1970
    return l.filter { now - (($0["time"] as? Double) ?? 0) < maxAge }
}

func writeList(_ l: [[String: Any]]) {
    if l.isEmpty { try? FileManager.default.removeItem(at: pendingFile); return }
    if let d = try? JSONSerialization.data(withJSONObject: ["captures": l]) {
        try? d.write(to: pendingFile, options: .atomic)
        chmod(pendingFile.path, 0o600) // page addresses and titles
    }
}

guard let msg = readMessage() else { exit(0) }
switch msg["cmd"] as? String {
case "pending":
    let l = readList()
    reply(["captures": l])
case "done":
    let times = (msg["times"] as? [Double]) ?? []
    let left = readList().filter { c in !times.contains { abs($0 - ((c["time"] as? Double) ?? 0)) < 0.001 } }
    writeList(left)
    log("added \(times.count) captured tab(s) to Claude's group")
    reply(["ok": true])
case "log":
    log(String(describing: msg["msg"] ?? "").prefix(300).description)
    reply(["ok": true])
default:
    reply(["error": "unknown command"])
}
