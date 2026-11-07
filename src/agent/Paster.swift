import AppKit
import ApplicationServices

enum DeliveryOutcome {
    case pasted
    case copiedOnly(String)   // reason; the Appshot text is left on the clipboard
}

/// Brings Claude forward and pastes the Appshot text, then the screenshot,
/// into the Code session's message box. Never presses Return. Restores the
/// clipboard afterwards.
enum Paster {
    static func deliver(_ r: CaptureResult) -> DeliveryOutcome {
        let pb = NSPasteboard.general
        guard let claude = NSRunningApplication.runningApplications(withBundleIdentifier: Paths.claudeBundleID).first else {
            setText(r.text, on: pb)
            return .copiedOnly("Claude isn't running")
        }
        let saved = PasteboardSnapshot(pb)

        activate(claude)
        guard waitForFrontmost(Paths.claudeBundleID, timeout: 2.0) else {
            setText(r.text, on: pb)
            return .copiedOnly("couldn't bring Claude forward")
        }
        Thread.sleep(forTimeInterval: 0.25)

        // Only a Claude Code session's message box; a chat composer or Claude's
        // own quick-entry box gets a copy instead.
        // shortcut: relies on Claude labelling that box "Prompt"; if pastes turn
        // into copies after a Claude update, check "label=" in appshots.log.
        let f = focusedField(claude.processIdentifier)
        log("paste target role=\(f.role ?? "nil") label=\(f.label ?? "")")
        guard f.role == "AXTextArea", f.label == "Prompt" else {
            setText(r.text, on: pb)
            return .copiedOnly("Claude wasn't showing a Code session's message box")
        }

        setText(r.text, on: pb)
        commandV()
        Thread.sleep(forTimeInterval: 0.45)

        if let img = r.image, let data = try? Data(contentsOf: URL(fileURLWithPath: img)) {
            pb.clearContents()
            let item = NSPasteboardItem()
            item.setData(data, forType: .png)
            if let tiff = NSImage(data: data)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
            pb.writeObjects([item])
            commandV()
            Thread.sleep(forTimeInterval: 0.7)
        }

        saved.restore(to: pb)
        return .pasted
    }

    private static func setText(_ s: String, on pb: NSPasteboard) {
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    private static func activate(_ app: NSRunningApplication) {
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(el, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate(options: [])
    }

    private static func waitForFrontmost(_ bundleID: String, timeout: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    private static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    /// Role and label (title, else description) of Claude's focused element.
    private static func focusedField(_ pid: pid_t) -> (role: String?, label: String?) {
        let app = AXUIElementCreateApplication(pid)
        // Electron only exposes its accessibility tree once asked.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetMessagingTimeout(app, 1.0)
        for _ in 0..<3 {
            if let v = attr(app, kAXFocusedUIElementAttribute) {
                let el = v as! AXUIElement
                let title = attr(el, kAXTitleAttribute) as? String
                let label = (title?.isEmpty == false) ? title : attr(el, kAXDescriptionAttribute) as? String
                return (attr(el, kAXRoleAttribute) as? String, label)
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return (nil, nil)
    }

    private static func commandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

/// A copy of everything on the clipboard, to put back afterwards.
struct PasteboardSnapshot {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    init(_ pb: NSPasteboard) {
        items = (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }
    }

    func restore(to pb: NSPasteboard) {
        pb.clearContents()
        let restored: [NSPasteboardItem] = items.map { pairs in
            let i = NSPasteboardItem()
            for (t, d) in pairs { i.setData(d, forType: t) }
            return i
        }
        if !restored.isEmpty { pb.writeObjects(restored) }
    }
}
