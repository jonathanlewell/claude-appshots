import AppKit

/// Fires when one modifier key (Option, Command or Control) is tapped twice
/// on its own: press and release, twice, quickly, with no other key,
/// modifier or click in between. Option+3 (#) or Option-click never count.
final class DoubleTapDetector {
    enum Key: String, CaseIterable {
        case option, command, control
        var flag: NSEvent.ModifierFlags {
            switch self { case .option: return .option; case .command: return .command; case .control: return .control }
        }
        var label: String {
            switch self { case .option: return "⌥ Option"; case .command: return "⌘ Command"; case .control: return "⌃ Control" }
        }
    }

    var key: Key
    private let onTrigger: () -> Void
    private var monitors: [Any] = []
    private var seenFirstEvent = false

    private var down = false
    private var downAt: TimeInterval = 0
    private var spoiled = false
    private var taps = 0
    private var lastTapUp: TimeInterval = 0

    private let maxHold: TimeInterval = 0.45
    private let maxGap: TimeInterval = 0.50

    init(key: Key, onTrigger: @escaping () -> Void) {
        self.key = key
        self.onTrigger = onTrigger
    }

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.handle(e) }) {
            monitors.append(g)
        } else {
            log("hotkey: global monitor NOT installed")
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.handle(e); return e }) {
            monitors.append(l)
        }
        log("hotkey: monitoring double-tap \(key.rawValue), monitors=\(monitors.count)")
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }

    private func handle(_ e: NSEvent) {
        if !seenFirstEvent { seenFirstEvent = true; log("hotkey: first event received type=\(e.type.rawValue)") }
        let now = e.timestamp
        guard e.type == .flagsChanged else { taps = 0; if down { spoiled = true }; return }

        let flags = e.modifierFlags.intersection([.shift, .control, .option, .command])
        let isDown = flags.contains(key.flag)

        if !down && isDown {
            down = true
            downAt = now
            spoiled = flags != key.flag
            if now - lastTapUp > maxGap { taps = 0 }
        } else if down && !isDown {
            down = false
            if !spoiled && flags.isEmpty && (now - downAt) <= maxHold {
                taps += 1
                lastTapUp = now
                if taps >= 2 {
                    taps = 0
                    log("hotkey: double-tap \(key.rawValue)")
                    onTrigger()
                }
            } else {
                taps = 0
            }
        } else if down {
            spoiled = true
            taps = 0
        } else {
            taps = 0
        }
    }
}
