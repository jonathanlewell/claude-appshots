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

        // A Code session's message box, or the composer of the chat or project
        // thread showing in Claude's main window. Claude's own quick-entry box
        // gets a copy instead. If focus is elsewhere in the window (say, a
        // message he clicked), move it to the box first.
        // shortcut: relies on Claude's labels ("Prompt" in Code, "Write your
        // reply/prompt to Claude" in chats); if pastes turn into copies after a
        // Claude update, check "label=" in appshots.log.
        let pid = claude.processIdentifier
        var f = focusedField(pid)
        log("paste target role=\(f.role ?? "nil") label=\(f.label ?? "") window=\(windowSubrole(pid) ?? "nil")")
        if !isPrompt(f, pid), focusOnlyPrompt(pid) { f = focusedField(pid); log("moved focus to the message box") }
        guard isPrompt(f, pid) else {
            setText(r.text, on: pb)
            return .copiedOnly("Claude wasn't showing a message box")
        }

        setText(r.text, on: pb, transient: true)
        guard pasteIfStillThere(pid) else {
            setText(r.text, on: pb)
            return .copiedOnly("Claude lost focus before pasting")
        }
        Thread.sleep(forTimeInterval: 0.45)

        if let img = r.image, let data = try? Data(contentsOf: URL(fileURLWithPath: img)) {
            pb.clearContents()
            let item = NSPasteboardItem()
            item.setData(data, forType: .png)
            if let tiff = NSImage(data: data)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
            item.setData(Data(), forType: transientType)
            pb.writeObjects([item])
            if pasteIfStillThere(pid) { Thread.sleep(forTimeInterval: 0.7) }
        }

        // Unless he copied something meanwhile, put his clipboard back.
        if pb.changeCount == ourChange { saved.restore(to: pb) }
        return .pasted
    }

    /// Marks clipboard contents that clipboard-history apps should not keep
    /// (nspasteboard.org convention), since an Appshot holds screen contents.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static var ourChange = 0

    private static func setText(_ s: String, on pb: NSPasteboard, transient: Bool = false) {
        pb.clearContents()
        pb.setString(s, forType: .string)
        if transient { pb.setData(Data(), forType: transientType) }
    }

    /// The Code tab's message box.
    private static let codeLabel = "Prompt"
    /// A chat's or project thread's composer: a new chat, then an existing one.
    private static let chatLabels: Set<String> = ["Write your prompt to Claude", "Write your reply to Claude"]

    /// Whether a label names a message box Appshots may paste into. Chat
    /// composers count only in Claude's main window, so Quick Entry (a floating
    /// panel) never gets the paste.
    static func isPromptLabel(_ label: String?, windowSubrole: String?) -> Bool {
        guard let label else { return false }
        if label == codeLabel { return true }
        return chatLabels.contains(label) && windowSubrole == "AXStandardWindow"
    }

    private static func isPrompt(_ f: (role: String?, label: String?), _ pid: pid_t) -> Bool {
        f.role == "AXTextArea" && isPromptLabel(f.label, windowSubrole: windowSubrole(pid))
    }

    /// Subrole of Claude's focused window: AXStandardWindow for the main window.
    private static func windowSubrole(_ pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        guard let w = attr(app, kAXFocusedWindowAttribute) else { return nil }
        return attr(w as! AXUIElement, kAXSubroleAttribute) as? String
    }

    /// ⌘V, only if Claude is still in front with the message box focused, so a
    /// window switch mid-paste can't send the Appshot to another app.
    private static func pasteIfStillThere(_ pid: pid_t) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              isPrompt(focusedField(pid), pid) else { return false }
        commandV()
        ourChange = NSPasteboard.general.changeCount
        return true
    }

    /// Focuses the message box in Claude's front window when there is exactly
    /// one (with two sessions side by side, which one he meant is unknowable).
    private static func focusOnlyPrompt(_ pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        guard let w = attr(app, kAXFocusedWindowAttribute) else { return false }
        let subrole = attr(w as! AXUIElement, kAXSubroleAttribute) as? String
        // Breadth-first, one round trip per element, skipping the inside of
        // each message ("Message 12") so a long conversation stays quick.
        let names = [kAXRoleAttribute, kAXDescriptionAttribute, kAXTitleAttribute, kAXChildrenAttribute] as CFArray
        var queue = [w as! AXUIElement], found: [AXUIElement] = [], i = 0
        let deadline = Date().addingTimeInterval(1.5)
        while i < queue.count, i < 5_000, Date() < deadline {
            let el = queue[i]; i += 1
            var vals: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(el, names, AXCopyMultipleAttributeOptions(rawValue: 0), &vals) == .success,
                  let v = vals as? [AnyObject], v.count == 4 else { continue }
            if v[0] as? String == "AXTextArea" {
                if isPromptLabel(v[1] as? String, windowSubrole: subrole) || isPromptLabel(v[2] as? String, windowSubrole: subrole) { found.append(el) }
            } else if !((v[1] as? String)?.hasPrefix("Message ") ?? false), let kids = v[3] as? [AXUIElement] {
                queue += kids
            }
        }
        let complete = i == queue.count
        log("message box search: \(found.count) found in \(i) elements, complete=\(complete)")
        guard found.count == 1, complete else { return false }
        AXUIElementSetAttributeValue(found[0], kAXFocusedAttribute as CFString, kCFBooleanTrue)
        Thread.sleep(forTimeInterval: 0.15)
        return true
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
