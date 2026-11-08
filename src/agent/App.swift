import AppKit
import ApplicationServices

/// Asks the launcher (which owns the app identity) to post a notification.
func notify(_ title: String, _ body: String) {
    let clean = { (s: String) in s.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
    FileHandle.standardOutput.write(Data("NOTIFY\t\(clean(title))\t\(clean(body))\n".utf8))
}

/// The agent has no icon or menu of its own (macOS won't show one for a
/// background program); the launcher owns them and sends commands on stdin.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var detector: DoubleTapDetector!
    private var paused = false
    private var busy = false
    private let work = DispatchQueue(label: "appshots.work")
    private var cleanupTimer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        try? FileManager.default.createDirectory(at: Paths.captures, withIntermediateDirectories: true)

        detector = DoubleTapDetector(key: .option) { [weak self] in self?.trigger() }
        detector.start()
        listenForCommands()

        Cleanup.run()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in Cleanup.run() }
        log("agent launched trusted=\(AXIsProcessTrusted()) screen=\(CGPreflightScreenCaptureAccess())")

        // Event monitors installed before Accessibility is granted never
        // receive key events, so reinstall them the moment it is.
        if !AXIsProcessTrusted() {
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
                guard AXIsProcessTrusted() else { return }
                t.invalidate()
                log("accessibility granted; restarting hotkey")
                self?.detector.start()
            }
        }
    }

    private func listenForCommands() {
        Thread.detachNewThread { [weak self] in
            while let line = readLine() {
                let parts = line.split(separator: " ").map(String.init)
                DispatchQueue.main.async { self?.command(parts) }
            }
            exit(0) // launcher went away
        }
    }

    private func command(_ parts: [String]) {
        switch parts.first {
        case "PAUSE":
            paused = parts.count > 1 && parts[1] == "1"
            log("paused=\(paused)")
        case "HOTKEY":
            if parts.count > 1, let k = DoubleTapDetector.Key(rawValue: parts[1]) {
                detector.key = k
                log("hotkey set to \(k.rawValue)")
            }
        case "CAPTURE":
            trigger(after: parts.count > 1 ? (Double(parts[1]) ?? 3) : 3)
        default:
            break
        }
    }

    // MARK: Capture

    private func trigger(after delay: TimeInterval = 0) {
        guard !paused else { log("trigger ignored: paused"); return }
        guard !busy else { log("trigger ignored: busy"); return }
        guard AXIsProcessTrusted() else {
            log("trigger ignored: not trusted")
            notify("Appshots needs Accessibility permission", "Open the menu bar icon → Permissions.")
            return
        }
        busy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            guard let front = NSWorkspace.shared.frontmostApplication,
                  let bid = front.bundleIdentifier,
                  bid != Paths.claudeBundleID else {
                log("trigger ignored: front app is Claude or unknown")
                busy = false
                return
            }
            let pid = front.processIdentifier
            work.async { [self] in
                let outcome: (String, String)
                // Never run a capture tool that isn't the one built here.
                let result = bundleIntact(Paths.app) ? CaptureRunner.run(pid: pid)
                    : .failure(.failed("Appshots' files changed since it was built. Run ~/.claude/appshots/install.sh"))
                switch result {
                case .failure(let e):
                    log("capture failed: \(e)")
                    outcome = ("Appshot failed", e.description)
                case .success(let r):
                    ChromeHandoff.record(r)
                    let title = "Appshot: \(r.app) — \(r.windowTitle)"
                    switch Paster.deliver(r) {
                    case .pasted:
                        let note = r.warnings.contains("screen-recording-not-granted") ? "Pasted without screenshot (needs Screen Recording)" : "Pasted into Claude"
                        outcome = (title, note)
                    case .copiedOnly(let why):
                        log("copied only: \(why)")
                        outcome = (title, "Copied — \(why). Click the message box and press ⌘V.")
                    }
                }
                DispatchQueue.main.async { [self] in
                    notify(outcome.0, outcome.1)
                    busy = false
                }
            }
        }
    }
}
