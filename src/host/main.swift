// Claude Appshots launcher.
//
// This is the only part macOS grants permissions to, and the only part that
// can show a menu bar icon, so it owns the icon and menu. build.sh signs it
// with this Mac's own certificate, which is what macOS ties the permissions
// to, so rebuilding keeps them.
//
// It starts the agent (Contents/MacOS/appshot-agent), which inherits those
// permissions and does the real work: hotkey, capture, paste. It first checks
// the whole app still matches this Mac's signature, so a swapped helper never
// gets those permissions.
//
// Agent → launcher (agent's stdout):   NOTIFY<TAB>title<TAB>body
// Launcher → agent (agent's stdin):    PAUSE 0|1 · HOTKEY option|command|control · CAPTURE <delay-seconds>

import AppKit
import ServiceManagement
import UserNotifications

let agentURL = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/appshot-agent")
let capturesURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/appshots/captures")

if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "").count > 1 {
    exit(0)
}

// MARK: Launcher

final class Launcher: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var agent: Process?
    private var agentIn: FileHandle?
    private var buffer = Data()
    private var quitting = false
    private var recentStarts: [Date] = []
    private var statusItem: NSStatusItem!

    // Taken elsewhere: ⌥⌥ by Claude's Quick Entry, ⌘⌘ by Siri if set to it.
    private let hotkeys: [(String, String)] = [("control", "⌃ Control"), ("command", "⌘ Command"), ("option", "⌥ Option")]
    private var paused: Bool {
        get { UserDefaults.standard.bool(forKey: "paused") }
        set { UserDefaults.standard.set(newValue, forKey: "paused") }
    }
    private var hotkey: String {
        get { UserDefaults.standard.string(forKey: "hotkey") ?? "control" }
        set { UserDefaults.standard.set(newValue, forKey: "hotkey") }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        // macOS puts a new icon at the left end of the icons, which on a notched
        // Mac is behind the notch, so start it near the clock (points from the
        // right edge). ⌘-drag it anywhere; macOS then keeps that spot.
        let spot = "NSStatusItem Preferred Position Item-0"
        if UserDefaults.standard.object(forKey: spot) == nil { UserDefaults.standard.set(250, forKey: spot) }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        if !UserDefaults.standard.bool(forKey: "didRegisterLoginItem") {
            UserDefaults.standard.set(true, forKey: "didRegisterLoginItem")
            try? SMAppService.mainApp.register()
        }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts), !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        startAgent()
    }

    func applicationWillTerminate(_ n: Notification) {
        quitting = true
        agent?.terminate()
    }

    // MARK: Agent

    private func startAgent() {
        guard !quitting else { return }
        recentStarts = recentStarts.filter { $0.timeIntervalSinceNow > -60 } + [Date()]
        guard recentStarts.count <= 5 else {
            post("Claude Appshots stopped", "The agent keeps crashing. Run ~/.claude/appshots/install.sh, then reopen the app.")
            return
        }
        guard bundleIntact(Bundle.main.bundleURL) else {
            post("Claude Appshots stopped", "Its files changed since it was built. Run ~/.claude/appshots/install.sh.")
            return
        }
        let p = Process()
        p.executableURL = agentURL
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardInput = inp
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            DispatchQueue.main.async { self?.consume(d) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, !self.quitting else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.startAgent() }
            }
        }
        do {
            try p.run()
            agent = p
            agentIn = inp.fileHandleForWriting
            send("HOTKEY \(hotkey)")
            send("PAUSE \(paused ? 1 : 0)")
        } catch {
            post("Claude Appshots", "Couldn't start the agent: \(error.localizedDescription)")
        }
    }

    private func send(_ line: String) {
        try? agentIn?.write(contentsOf: Data((line + "\n").utf8))
    }

    private func consume(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...nl)
            let parts = line.components(separatedBy: "\t")
            if parts.first == "NOTIFY" {
                post(parts.count > 1 ? parts[1] : "", parts.count > 2 ? parts[2] : "")
            }
        }
    }

    private func post(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let label = hotkeys.first { $0.0 == hotkey }?.1 ?? hotkey
        let state: String
        if !AXIsProcessTrusted() { state = "Needs Accessibility permission" }
        else if paused { state = "Paused" }
        else { state = "Ready — double-tap \(label)" }
        disabled(menu, "Claude Appshots: \(state)")
        if !CGPreflightScreenCaptureAccess() { disabled(menu, "Screenshots off — needs Screen Recording") }
        menu.addItem(.separator())
        menu.addItem(item(paused ? "Resume" : "Pause", #selector(togglePause)))
        menu.addItem(item("Capture front window in 3 seconds", #selector(delayedCapture)))
        menu.addItem(item("Open captures folder", #selector(openFolder)))
        let hk = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (key, name) in hotkeys {
            let i = item("Double-tap \(name)", #selector(chooseHotkey(_:)))
            i.representedObject = key
            i.state = key == hotkey ? .on : .off
            sub.addItem(i)
        }
        hk.submenu = sub
        menu.addItem(hk)
        menu.addItem(.separator())
        menu.addItem(item("Permissions…", #selector(openPermissions)))
        let q = item("Quit Claude Appshots", #selector(quit))
        q.keyEquivalent = "q"
        menu.addItem(q)
    }

    private func disabled(_ menu: NSMenu, _ title: String) {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        menu.addItem(i)
    }

    private func item(_ title: String, _ sel: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        return i
    }

    private func updateIcon() {
        let img = NSImage(systemSymbolName: paused ? "pause.circle" : "camera.viewfinder", accessibilityDescription: "Claude Appshots")
        img?.isTemplate = true
        statusItem.button?.image = img
    }

    @objc private func togglePause() { paused.toggle(); updateIcon(); send("PAUSE \(paused ? 1 : 0)") }
    @objc private func delayedCapture() { send("CAPTURE 3") }
    @objc private func openFolder() { NSWorkspace.shared.open(capturesURL) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func chooseHotkey(_ sender: NSMenuItem) {
        guard let k = sender.representedObject as? String else { return }
        hotkey = k
        send("HOTKEY \(k)")
    }

    @objc private func openPermissions() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        if trusted, !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        let pane = trusted ? "Privacy_ScreenCapture" : "Privacy_Accessibility"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

let app = NSApplication.shared
let launcher = Launcher()
app.delegate = launcher
app.setActivationPolicy(.accessory)
app.run()
