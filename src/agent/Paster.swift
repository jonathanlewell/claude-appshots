import AppKit
import ApplicationServices

enum DeliveryOutcome {
    case pasted
    case copiedOnly(String)   // reason; the Appshot text is left on the clipboard
}

/// Brings Claude forward and pastes the Appshot text, then the screenshot,
/// into whatever has focus there. Never presses Return. Restores the
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

        let f = focused(claude.processIdentifier)
        log("paste target role=\(f.role ?? "nil") label=\(f.label ?? "") placeholder=\(f.placeholder ?? "") window=\(f.windowSize)")
        guard let role = f.role, editableRoles.contains(role) else {
            setText(r.text, on: pb)
            return .copiedOnly("Claude's message box wasn't focused")
        }
        // Only a Claude Code session's message box: it is labelled "Prompt" and
        // its placeholder mentions sending. Anything else (a chat composer,
        // Claude's own quick-entry box, a search field) gets a copy instead.
        guard f.label == "Prompt" || (f.placeholder ?? "").contains("to send") else {
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

    private static let editableRoles: Set<String> = ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"]

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

    struct Focus { var role, label, placeholder: String?; var windowSize = "?" }

    private static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    private static func focused(_ pid: pid_t) -> Focus {
        let app = AXUIElementCreateApplication(pid)
        // Electron only exposes its accessibility tree once asked.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetMessagingTimeout(app, 1.0)
        for _ in 0..<3 {
            if let v = attr(app, kAXFocusedUIElementAttribute) {
                let el = v as! AXUIElement
                var f = Focus()
                f.role = attr(el, kAXRoleAttribute) as? String
                let title = attr(el, kAXTitleAttribute) as? String
                let desc = attr(el, kAXDescriptionAttribute) as? String
                f.label = (title?.isEmpty == false ? title : desc)
                f.placeholder = attr(el, kAXPlaceholderValueAttribute) as? String
                if let w = attr(el, kAXWindowAttribute), let sv = attr(w as! AXUIElement, kAXSizeAttribute) {
                    var size = CGSize.zero
                    AXValueGetValue(sv as! AXValue, .cgSize, &size)
                    f.windowSize = "\(Int(size.width))x\(Int(size.height))"
                }
                if f.role != nil { return f }
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return Focus()
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
