import AppKit

enum Paths {
    static let home = ProcessInfo.processInfo.environment["HOME"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser
    static let base = home.appendingPathComponent(".claude/appshots")
    static let chrome = home.appendingPathComponent("Library/Application Support/Google/Chrome")
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
    /// The time in the capture's file names ("2026-11-19T06-44-40.415Z"). A
    /// Claude session quotes it to the Chrome bridge to ask for this tab.
    var stamp: String? = nil

    /// The same capture with an extra attribute on the pasted `<appshot>` tag.
    func adding(attribute name: String, _ value: String) -> CaptureResult {
        let v = value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        guard let r = text.range(of: "<appshot ") else { return self }
        let t = text.replacingCharacters(in: r, with: "<appshot \(name)=\"\(v)\" ")
        return CaptureResult(text: t, image: image, app: app, bundleID: bundleID, windowTitle: windowTitle, url: url, warnings: warnings, stamp: stamp)
    }
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
            warnings: obj["warnings"] as? [String] ?? [],
            stamp: (obj["tree"] as? String).flatMap(stamp(fromPath:))))
    }

    /// ".../Google Chrome Appshot 2026-11-19T06-44-40.415Z.txt" → "2026-11-19T06-44-40.415Z"
    static func stamp(fromPath path: String) -> String? {
        let name = (path as NSString).lastPathComponent
        guard let r = name.range(of: " Appshot ", options: .backwards) else { return nil }
        let s = (name[r.upperBound...] as Substring).replacingOccurrences(of: ".txt", with: "").replacingOccurrences(of: ".png", with: "")
        return s.isEmpty ? nil : s
    }
}

/// Tells the Chrome bridge which tab was just captured. The bridge (a small
/// Chrome extension plus native host) adds that tab to a Claude session's tab
/// group when the session asks for it by stamp, so Claude controls the real
/// tab. Each note expires after 15 minutes and is used once.
enum ChromeHandoff {
    static let file = Paths.base.appendingPathComponent("chrome-pending.json")

    /// Records the note and returns which profile the tab is in and whether the
    /// bridge can see it (nil when that can't be told).
    @discardableResult
    static func record(_ r: CaptureResult) -> ChromeBridge.Status? {
        guard r.bundleID == "com.google.Chrome" else { return nil }
        let status = ChromeBridge.status(windowTitle: r.windowTitle)
        if let s = status, !s.installed { log("chrome-handoff: bridge not installed in Chrome profile dir=\(s.profileDir)") }
        let now = Date().timeIntervalSince1970
        // Keep every capture from the last 15 minutes, so several tabs can be
        // handed over at once; drop an older note for the same page.
        var list: [[String: Any]] = []
        if let d = try? Data(contentsOf: file),
           let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
           let old = o["captures"] as? [[String: Any]] {
            list = old.filter { (now - (($0["time"] as? Double) ?? 0)) < 15 * 60 && ($0["url"] as? String) != r.url }
        }
        var note: [String: Any] = ["time": now, "url": r.url ?? "", "windowTitle": r.windowTitle]
        if let s = r.stamp { note["stamp"] = s }
        list.append(note)
        if let d = try? JSONSerialization.data(withJSONObject: ["captures": list]) {
            try? d.write(to: file, options: .atomic)
            chmod(file.path, 0o600)
        }
        return status
    }
}

/// The bridge is a Chrome extension, and Chrome installs extensions per
/// profile: a tab captured in a profile without it is never moved (for
/// example, captures from a "Work" profile when the bridge is only in Default). This works out the captured window's profile
/// from its title and checks that profile's own extension list.
enum ChromeBridge {
    /// Fixed by the key in chrome-extension/manifest.json (install.sh derives it the same way).
    static let extensionID = "eiomachhgadhcohiceonjfnonjkhaach"

    struct Status: Equatable {
        let profileName: String
        let profileDir: String
        let installed: Bool
    }

    /// "Page - Google Chrome – Work" → "Work". Chrome only adds the profile
    /// name when there is more than one profile.
    static func profileName(fromTitle title: String) -> String? {
        guard let r = title.range(of: "Google Chrome", options: .backwards) else { return nil }
        var rest = title[r.upperBound...].trimmingCharacters(in: .whitespaces)
        if let first = rest.first, "–—-".contains(first) { rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces) }
        return rest.isEmpty ? nil : rest
    }

    static func status(windowTitle: String, chromeDir: URL = Paths.chrome) -> Status? {
        guard let state = json(chromeDir.appendingPathComponent("Local State")),
              let profile = state["profile"] as? [String: Any] else { return nil }
        let cache = (profile["info_cache"] as? [String: [String: Any]]) ?? [:]
        let dir: String
        if let name = profileName(fromTitle: windowTitle) {
            let hits = cache.filter { ($0.value["name"] as? String) == name }.map(\.key)
            guard hits.count == 1 else { return nil } // unknown or ambiguous: don't guess
            dir = hits[0]
        } else {
            guard cache.count <= 1 else { return nil } // several profiles but no name in the title
            dir = cache.keys.first ?? (profile["last_used"] as? String) ?? "Default"
        }
        let name = (cache[dir]?["name"] as? String) ?? dir
        return Status(profileName: name, profileDir: dir, installed: installed(inProfile: dir, chromeDir: chromeDir))
    }

    static func installed(inProfile dir: String, chromeDir: URL = Paths.chrome) -> Bool {
        let folder = chromeDir.appendingPathComponent(dir)
        for file in ["Preferences", "Secure Preferences"] {
            guard let prefs = json(folder.appendingPathComponent(file)),
                  let settings = (prefs["extensions"] as? [String: Any])?["settings"] as? [String: Any],
                  let ext = settings[extensionID] as? [String: Any] else { continue }
            // Switched off in chrome://extensions counts as missing.
            if let reasons = ext["disable_reasons"] as? [Any], !reasons.isEmpty { return false }
            if let reasons = ext["disable_reasons"] as? Int, reasons != 0 { return false }
            if let state = ext["state"] as? Int, state == 0 { return false }
            return true
        }
        return false
    }

    private static func json(_ url: URL) -> [String: Any]? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
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
