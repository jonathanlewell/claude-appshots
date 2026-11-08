import AppKit

enum Paths {
    static let base = (ProcessInfo.processInfo.environment["HOME"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser).appendingPathComponent(".claude/appshots")
    static let captures = base.appendingPathComponent("captures")
    /// The app bundle this agent runs from, and the capture tool inside it.
    static let app = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let captureTool = app.appendingPathComponent("Contents/MacOS/appshot-capture")
    static let log = base.appendingPathComponent("appshots.log")
    static let claudeBundleID = "com.anthropic.claudefordesktop"
}

/// Metadata only; no captured content is ever logged.
func log(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    if let h = try? FileHandle(forWritingTo: Paths.log) {
        h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
    } else {
        try? line.write(to: Paths.log, atomically: true, encoding: .utf8)
    }
}

struct CaptureResult {
    let text: String
    let image: String?
    let app: String
    let bundleID: String
    let windowTitle: String
    let url: String?
    let warnings: [String]
}

enum CaptureError: Error, CustomStringConvertible {
    case toolMissing, failed(String), timeout
    var description: String {
        switch self {
        case .toolMissing: return "capture tool missing — run install.sh"
        case .failed(let s): return s
        case .timeout: return "capture timed out"
        }
    }
}

/// Runs the capture tool as a child process, which inherits this app's
/// Accessibility and Screen Recording permissions.
enum CaptureRunner {
    static func run(pid: pid_t) -> Result<CaptureResult, CaptureError> {
        guard FileManager.default.isExecutableFile(atPath: Paths.captureTool.path) else { return .failure(.toolMissing) }
        let p = Process()
        p.executableURL = Paths.captureTool
        p.arguments = ["--pid", String(pid), "--outdir", Paths.captures.path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return .failure(.failed("could not start capture tool")) }

        var data = Data()
        let reader = DispatchQueue(label: "appshots.read")
        let done = DispatchSemaphore(value: 0)
        reader.async { data = out.fileHandleForReading.readDataToEndOfFile(); done.signal() }
        if done.wait(timeout: .now() + 20) == .timedOut { p.terminate(); return .failure(.timeout) }
        p.waitUntilExit()

        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failure(.failed("capture tool returned nothing"))
        }
        if let err = obj["error"] as? String { return .failure(.failed(err)) }
        guard let text = obj["text"] as? String else { return .failure(.failed("no text")) }
        log("captured app=\(obj["bundleID"] ?? "?") nodes=\(obj["nodes"] ?? "?") pasted=\(text.count) chars warnings=\(obj["warnings"] ?? [])")
        return .success(CaptureResult(
            text: text,
            image: obj["image"] as? String,
            app: obj["app"] as? String ?? "App",
            bundleID: obj["bundleID"] as? String ?? "",
            windowTitle: obj["windowTitle"] as? String ?? "",
            url: obj["url"] as? String,
            warnings: obj["warnings"] as? [String] ?? []))
    }
}

/// Tells the Chrome bridge which tab was just captured. The bridge (a small
/// Chrome extension plus native host) adds that tab to Claude in Chrome's tab
/// group as soon as Claude creates or uses one, so Claude controls the real
/// tab. Each note expires after 15 minutes and is used once.
enum ChromeHandoff {
    static let file = Paths.base.appendingPathComponent("chrome-pending.json")

    static func record(_ r: CaptureResult) {
        guard r.bundleID == "com.google.Chrome" else { return }
        let now = Date().timeIntervalSince1970
        // Keep every capture from the last 15 minutes, so several tabs can be
        // handed over at once; drop an older note for the same page.
        var list: [[String: Any]] = []
        if let d = try? Data(contentsOf: file),
           let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
           let old = o["captures"] as? [[String: Any]] {
            list = old.filter { (now - (($0["time"] as? Double) ?? 0)) < 15 * 60 && ($0["url"] as? String) != r.url }
        }
        list.append(["time": now, "url": r.url ?? "", "windowTitle": r.windowTitle])
        if let d = try? JSONSerialization.data(withJSONObject: ["captures": list]) {
            try? d.write(to: file, options: .atomic)
            chmod(file.path, 0o600)
        }
    }
}

enum Cleanup {
    /// Deletes captures older than 24 hours and keeps the log under 1 MB.
    static func run() {
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: Paths.log.path))?[.size] as? Int, size > 1_000_000 {
            let old = Paths.log.appendingPathExtension("1")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: Paths.log, to: old)
        }
        guard let items = try? fm.contentsOfDirectory(at: Paths.captures, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        var removed = 0
        for url in items {
            let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
            if d < cutoff, (try? fm.removeItem(at: url)) != nil { removed += 1 }
        }
        if removed > 0 { log("cleanup removed=\(removed)") }
    }
}
