import AppKit
import IOKit
import IOKit.hidsystem

/// Used only when the TSM request can't be made: TISSelectInputSource, then
/// make the focused app re-read the input source by moving key focus away and
/// back. "panel" uses a non-activating panel (how Spotlight takes focus, so
/// the frontmost app stays active); "activate" activates hantap like
/// macism's TemporaryWindow.
enum FallbackMode: String {
    case panel, activate, none
}

private final class NudgePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

enum Fallback {
    private static var panel: NudgePanel?

    static func nudge(mode: FallbackMode, ms: Int) {
        switch mode {
        case .none: return
        case .panel: nudgePanel(ms: ms)
        case .activate: nudgeActivate(ms: ms)
        }
    }

    private static func makePanel(nonActivating: Bool) -> NudgePanel {
        let frame = NSRect(x: 0, y: 0, width: 2, height: 2)
        let p = NudgePanel(contentRect: frame,
                           styleMask: nonActivating ? [.nonactivatingPanel, .borderless] : [.borderless],
                           backing: .buffered, defer: false)
        p.level = .screenSaver
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        if let screen = NSScreen.main {
            p.setFrameOrigin(NSPoint(x: screen.frame.maxX - 2, y: screen.frame.minY))
        }
        // A text field as first responder gives TSM an input context to activate.
        let field = NSTextField(frame: frame)
        field.isBordered = false
        field.drawsBackground = false
        p.contentView?.addSubview(field)
        p.initialFirstResponder = field
        return p
    }

    private static func nudgePanel(ms: Int) {
        let p = panel ?? makePanel(nonActivating: true)
        panel = p
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(p.initialFirstResponder)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) {
            p.orderOut(nil)
        }
    }

    private static func nudgeActivate(ms: Int) {
        let previous = NSWorkspace.shared.frontmostApplication
        let p = makePanel(nonActivating: false)
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) {
            p.orderOut(nil)
            previous?.activate()
        }
    }
}

enum CapsLockState {
    static func toggle() {
        guard let on = get() else { return }
        set(!on)
    }

    static func get() -> Bool? {
        withConnection { conn in
            var state = false
            return IOHIDGetModifierLockState(conn, Int32(kIOHIDCapsLockState), &state) == KERN_SUCCESS ? state : nil
        } ?? nil
    }

    static func set(_ on: Bool) {
        _ = withConnection { conn in IOHIDSetModifierLockState(conn, Int32(kIOHIDCapsLockState), on) }
    }

    private static func withConnection<T>(_ body: (io_connect_t) -> T) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &conn) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(conn) }
        return body(conn)
    }
}
