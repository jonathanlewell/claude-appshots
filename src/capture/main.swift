// appshot-capture
//
// Builds a Codex-style <appshot> block for one app's front window: header,
// accessibility tree, focused element or selected text, plus a screenshot.
//
// It is run by the Appshots agent inside "Claude Appshots.app", which holds
// the Accessibility and Screen Recording permissions; a child process
// inherits them. Run on its own from a terminal it reports that permission is
// missing.
//
// Usage: appshot-capture --pid N [--outdir DIR]
// Saves the full Codex-format Appshot (tree) and a screenshot to DIR, and
// prints one JSON object whose "text" is the short block to paste.

import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

var argPID: pid_t?
var outDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude/appshots/captures").path // --outdir overrides
var args = CommandLine.arguments.dropFirst().makeIterator()
while let a = args.next() {
    if a == "--pid" { argPID = args.next().flatMap { pid_t($0) } }
    if a == "--outdir", let v = args.next() { outDir = v }
}

func emit(_ obj: [String: Any]) -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(obj["error"] == nil ? 0 : 1)
}

guard AXIsProcessTrusted() else { emit(["error": "accessibility-not-granted"]) }

guard let target = argPID.flatMap({ NSRunningApplication(processIdentifier: $0) }) else { emit(["error": "app-not-found"]) }

let appName = target.localizedName ?? target.bundleIdentifier ?? "App"
let bundleID = target.bundleIdentifier ?? ""
let appEl = AXUIElementCreateApplication(target.processIdentifier)
AXUIElementSetMessagingTimeout(appEl, 1.5)

// MARK: - AX helpers

let attrNames: [String] = [
    kAXRoleAttribute, kAXRoleDescriptionAttribute, kAXSubroleAttribute,
    kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute,
    kAXPlaceholderValueAttribute, kAXURLAttribute, kAXSelectedAttribute,
    kAXChildrenAttribute, "AXDocument",
]

func fetch(_ el: AXUIElement) -> [String: AnyObject] {
    var values: CFArray?
    let err = AXUIElementCopyMultipleAttributeValues(el, attrNames as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &values)
    guard err == .success, let arr = values as? [AnyObject] else { return [:] }
    var out: [String: AnyObject] = [:]
    for (i, v) in arr.enumerated() where i < attrNames.count {
        if CFGetTypeID(v) == AXValueGetTypeID(), AXValueGetType(v as! AXValue) == .axError { continue }
        out[attrNames[i]] = v
    }
    return out
}

func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}

func setFlag(_ el: AXUIElement, _ name: String, _ on: Bool) {
    AXUIElementSetAttributeValue(el, name as CFString, (on ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef)
}

func nonEmpty(_ v: AnyObject?) -> String? {
    guard let s = v as? String else { return nil }
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}

func oneLine(_ s: String, limit: Int = 2_000) -> String {
    var t = s.replacingOccurrences(of: "\r\n", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\t", with: " ")
    if t.count > limit { t = String(t.prefix(limit)) + "…" }
    return t
}

func esc(_ s: String, attribute: Bool = false) -> String {
    var t = s.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
    if attribute { t = t.replacingOccurrences(of: "\"", with: "&quot;") }
    return t
}

func shortURL(_ s: String) -> String {
    for p in ["https://", "http://"] where s.hasPrefix(p) { return String(s.dropFirst(p.count)) }
    return s
}

func urlString(_ a: [String: AnyObject]) -> String? {
    if let u = a[kAXURLAttribute] as? URL { return shortURL(u.absoluteString) }
    if let d = nonEmpty(a["AXDocument"]) { return shortURL(d) }
    return nil
}

/// (display text, type tag for the state list)
func displayValue(_ v: AnyObject) -> (String, String?)? {
    if CFGetTypeID(v) == CFBooleanGetTypeID() { return ((v as! Bool) ? "on" : "off", "boolean") }
    if let n = v as? NSNumber {
        let d = n.doubleValue
        return d == d.rounded() ? (String(Int(d)), "integer") : (n.stringValue, "number")
    }
    if let s = v as? String { return (s, nil) }
    if let u = v as? URL { return (shortURL(u.absoluteString), nil) }
    return nil
}

func isSecure(_ a: [String: AnyObject]) -> Bool {
    (a[kAXSubroleAttribute] as? String) == kAXSecureTextFieldSubrole
}

/// One element as a Codex-style line, without indentation.
func describe(_ el: AXUIElement, _ a: [String: AnyObject]) -> String? {
    let role = (a[kAXRoleAttribute] as? String) ?? ""
    // Codex's wording: macOS says "group", Codex says "container".
    let roleDesc = role == kAXGroupRole ? "container" : (nonEmpty(a[kAXRoleDescriptionAttribute]) ?? role)
    let title = nonEmpty(a[kAXTitleAttribute])
    let desc = nonEmpty(a[kAXDescriptionAttribute])
    let secure = isSecure(a)
    let url = urlString(a)

    var value: (String, String?)?
    if !secure, role != "AXHeading", let v = a[kAXValueAttribute] { value = displayValue(v) }
    if let v = value, v.0.isEmpty { value = nil }

    var states: [String] = []
    if (a[kAXSelectedAttribute] as? Bool) == true { states.append("selected") }
    if value != nil {
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(el, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue {
            states.append("settable")
            if let tag = value?.1 { states.append(tag) }
        }
    }

    var label: String?
    var extras: [String] = []
    if role == kAXStaticTextRole {
        label = value.map { $0.0 }.flatMap { $0.isEmpty ? nil : $0 } ?? title ?? desc
        value = nil
    } else {
        label = title ?? desc
        if title != nil, let d = desc, d != title { extras.append("Description: \(oneLine(d))") }
    }
    if let p = nonEmpty(a[kAXPlaceholderValueAttribute]) { extras.append("Placeholder: \(oneLine(p))") }
    if secure { extras.append("Value: (hidden)") }
    if let (v, _) = value, !v.isEmpty, v != label { extras.append("Value: \(oneLine(v, limit: 4_000))") }
    if let u = url {
        extras.append(role == "AXLink" && value == nil ? "Value: \(u)" : "URL: \(u)")
    }

    let hasChildren = ((a[kAXChildrenAttribute] as? [AXUIElement])?.isEmpty == false)
    if label == nil, extras.isEmpty, !hasChildren, [kAXGroupRole, kAXUnknownRole, ""].contains(role) {
        return nil // empty leaf container: noise
    }

    var line = roleDesc
    if !states.isEmpty { line += " (\(states.joined(separator: ", ")))" }
    if let l = label { line += " \(oneLine(l))" }
    if !extras.isEmpty { line += (label == nil ? " " : ", ") + extras.joined(separator: ", ") }
    return esc(line)
}

// MARK: - Tree walk

let maxDepth = 60
let maxNodes = 8_000

struct Walk {
    var lines: [String] = []
    var nodes = 0
    var firstWebURL: String?
    var emptyWebArea = false
    var hitNodeLimit = false
    var hitTimeLimit = false
}

let walkDeadline = Date().addingTimeInterval(6)

func walk(_ el: AXUIElement, depth: Int, into w: inout Walk) {
    if w.nodes >= maxNodes { w.hitNodeLimit = true; return }
    if w.nodes % 50 == 0, Date() > walkDeadline { w.hitTimeLimit = true; return }
    w.nodes += 1
    let a = fetch(el)
    let children = (a[kAXChildrenAttribute] as? [AXUIElement]) ?? []
    let role = (a[kAXRoleAttribute] as? String) ?? ""
    let windowButtons: Set<String> = ["AXCloseButton", "AXMinimizeButton", "AXFullScreenButton", "AXZoomButton"]
    if let sub = a[kAXSubroleAttribute] as? String, windowButtons.contains(sub) { return }
    if role == "AXWebArea" {
        if w.firstWebURL == nil { w.firstWebURL = urlString(a) }
        if children.isEmpty { w.emptyWebArea = true }
    }
    var childDepth = depth
    if let line = describe(el, a) {
        w.lines.append(String(repeating: "\t", count: depth) + line)
        childDepth = depth + 1
    }
    guard childDepth <= maxDepth else { return }
    for c in children { walk(c, depth: childDepth, into: &w) }
}

// MARK: - Window

func frontWindow() -> AXUIElement? {
    if let w = attr(appEl, kAXFocusedWindowAttribute) { return (w as! AXUIElement) }
    if let w = attr(appEl, kAXMainWindowAttribute) { return (w as! AXUIElement) }
    if let ws = attr(appEl, kAXWindowsAttribute) as? [AXUIElement] { return ws.first }
    return nil
}

// Electron and Chromium only build their accessibility tree for assistive apps.
setFlag(appEl, "AXManualAccessibility", true)

guard let window = frontWindow() else { emit(["error": "no-window", "app": appName]) }
let windowTitle = nonEmpty(attr(window, kAXTitleAttribute)) ?? appName

var tree = Walk()
walk(window, depth: 0, into: &tree)

if (tree.emptyWebArea || tree.nodes < 4) && !tree.hitTimeLimit {
    // Chromium sometimes needs the older switch and a moment to build the tree.
    // Put it back as found: VoiceOver users have it on.
    let wasOn = (attr(appEl, "AXEnhancedUserInterface") as? Bool) == true
    setFlag(appEl, "AXEnhancedUserInterface", true)
    Thread.sleep(forTimeInterval: 0.8)
    tree = Walk()
    walk(window, depth: 0, into: &tree)
    if !wasOn { setFlag(appEl, "AXEnhancedUserInterface", false) }
}

if let first = tree.lines.first, !first.contains("URL: "), let u = tree.firstWebURL {
    tree.lines[0] = first + ", URL: " + esc(u)
}

// MARK: - Footer: selected text or focused element

var selection: String?
var focusLine: String?
if let f = attr(appEl, kAXFocusedUIElementAttribute).map({ $0 as! AXUIElement }) {
    let fa = fetch(f)
    if !isSecure(fa) { selection = nonEmpty(attr(f, kAXSelectedTextAttribute)) }
    if selection == nil { focusLine = describe(f, fa) }
}

// MARK: - Assemble and save

let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: TimeZone(identifier: "UTC")!,
                                        formatOptions: [.withInternetDateTime, .withFractionalSeconds])
    .replacingOccurrences(of: ":", with: "-")
// An app name is chosen by the app; "/" in it must not lead outside outDir.
let baseName = "\(appName.replacingOccurrences(of: "/", with: "-")) Appshot \(stamp)"
// Screen contents: readable by this user only.
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
chmod(outDir, 0o700)
let treePath = (outDir as NSString).appendingPathComponent(baseName + ".txt")
let imageName = baseName + ".png"
let imagePath = (outDir as NSString).appendingPathComponent(imageName)
let url = tree.firstWebURL

// The tree file is Codex's format, line for line.
var full = "<appshot app=\"\(esc(appName, attribute: true))\" bundle-identifier=\"\(esc(bundleID, attribute: true))\" window-title=\"\(esc(windowTitle, attribute: true))\" image=\"\(esc(imageName, attribute: true))\">"
full += "\nWindow: \"\(esc(windowTitle))\", App: \(esc(appName)).\n" + tree.lines.joined(separator: "\n")
if tree.hitNodeLimit { full += "\n[Tree stopped after \(maxNodes) elements.]" }
if tree.hitTimeLimit { full += "\n[Tree stopped after 6 seconds; \(tree.nodes) elements read. The app was slow to answer.]" }
if let sel = selection {
    full += "\n\nSelected text: ```\n\(esc(String(sel.prefix(6_000))))\n```\n\n"
        + "Note: The user had this text selected when they took the Appshot. If they ask about \"this\" or refer to what they are looking at, they may mean the selection, though they may also mean something else on screen."
} else if let f = focusLine {
    full += "\n\nThe focused UI element is \(f)"
}
full += "\n</appshot>"
try? full.write(toFile: treePath, atomically: true, encoding: .utf8)

// The pasted block: who and where, the selection or focus, and the tree's path.
var short = "<appshot app=\"\(esc(appName, attribute: true))\" bundle-identifier=\"\(esc(bundleID, attribute: true))\" window-title=\"\(esc(windowTitle, attribute: true))\""
if let url { short += " url=\"\(esc(url, attribute: true))\"" }
short += " image=\"\(esc(imageName, attribute: true))\" tree=\"\(esc(treePath, attribute: true))\">"
if let sel = selection {
    short += "\nSelected: " + esc(sel.count > 1_000 ? String(sel.prefix(1_000)) + " […]" : sel)
} else if let f = focusLine {
    // A focused container can describe a whole page; the tree file has it all.
    short += "\nFocused: " + (f.count > 300 ? String(f.prefix(300)).replacingOccurrences(of: "&[a-z]*$", with: "", options: .regularExpression) + " […]" : f)
}
short += "\n</appshot>"

// MARK: - Screenshot

var warnings: [String] = []
var savedImage: String?
if !CGPreflightScreenCaptureAccess() {
    warnings.append("screen-recording-not-granted")
} else {
    var wid: CGWindowID = 0
    if _AXUIElementGetWindow(window, &wid) == .success, wid != 0 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", String(wid), "-t", "png", imagePath]
        try? p.run(); p.waitUntilExit()
        if FileManager.default.fileExists(atPath: imagePath) {
            let s = Process()
            s.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            s.arguments = ["-Z", "2048", imagePath]
            s.standardOutput = FileHandle.nullDevice; s.standardError = FileHandle.nullDevice
            try? s.run(); s.waitUntilExit()
            savedImage = imagePath
        } else {
            warnings.append("screenshot-failed")
        }
    } else {
        warnings.append("no-window-id")
    }
}

var result: [String: Any] = [
    "text": short,
    "tree": treePath,
    "app": appName,
    "bundleID": bundleID,
    "windowTitle": windowTitle,
    "nodes": tree.nodes,
    "warnings": warnings,
]
if let url { result["url"] = url }
if let savedImage { result["image"] = savedImage }
emit(result)
