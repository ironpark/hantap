import AppKit
import Carbon

struct Config {
    var korean: String?
    var latin: String?
    /// Holding CapsLock this long reverts the switch and toggles CapsLock. 0 disables.
    var holdMs = 500
    var fallback: FallbackMode = .panel
    var nudgeMs = 60

    static func parse(_ args: [String]) -> Config {
        var c = Config()
        var it = args.makeIterator()
        while let a = it.next() {
            switch a {
            case "--korean": c.korean = it.next()
            case "--latin": c.latin = it.next()
            case "--hold-ms": c.holdMs = it.next().flatMap(Int.init) ?? c.holdMs
            case "--nudge-ms": c.nudgeMs = it.next().flatMap(Int.init) ?? c.nudgeMs
            case "--fallback":
                guard let m = it.next().flatMap(FallbackMode.init(rawValue:)) else {
                    fail("--fallback takes panel, activate or none")
                }
                c.fallback = m
            default: fail("unknown option \(a)")
            }
        }
        return c
    }
}

private let logDateFormat: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
}()

func log(_ s: String) {
    FileHandle.standardError.write(Data("\(logDateFormat.string(from: Date())) \(s)\n".utf8))
}

func fail(_ s: String) -> Never {
    log("error: \(s)")
    exit(1)
}

private func ms(_ seconds: TimeInterval) -> String { String(format: "%.1fms", seconds * 1000) }

/// Switching shared by the agent and the one-shot commands.
final class Switcher {
    let config: Config
    let tsm = TSMSwitch()
    let korean: TISInputSource
    let latin: TISInputSource
    let koreanID: String
    private var trackedID: String
    private var lastSwitch: TimeInterval = 0

    init(config: Config) {
        self.config = config
        guard let pair = InputSources.resolvePair(korean: config.korean, latin: config.latin) else {
            fail("no Korean / Latin input source enabled (see `hantap list`)")
        }
        korean = pair.korean
        latin = pair.latin
        koreanID = InputSources.id(korean)
        trackedID = InputSources.currentID()
        if !tsm.available { log("warning: private TSM symbols missing, every switch uses the fallback") }
    }

    /// Right after our own switch the system-wide source may lag behind the
    /// app, so a quick second press toggles from what we last selected.
    func currentID() -> String {
        ProcessInfo.processInfo.systemUptime - lastSwitch < 0.4 ? trackedID : InputSources.currentID()
    }

    func toggleTarget() -> TISInputSource {
        currentID() == koreanID ? latin : korean
    }

    @discardableResult
    func select(_ to: TISInputSource, reason: String, keyTime: TimeInterval? = nil) -> Bool {
        let t1 = ProcessInfo.processInfo.systemUptime
        let result = tsm.select(to)
        var method: String
        var ok = true
        switch result {
        case .tsm:
            method = "tsm"
        case .failed(let why):
            ok = false
            TISSelectInputSource(to)
            method = "tis (\(why))"
            if InputSources.isCJKV(to) && config.fallback != .none {
                Fallback.nudge(mode: config.fallback, ms: config.nudgeMs)
                method += " + \(config.fallback.rawValue) nudge"
            }
        }
        let t2 = ProcessInfo.processInfo.systemUptime
        trackedID = InputSources.id(to)
        lastSwitch = t2

        let pid = tsm.keyFocusPID()
        let app = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier } ?? "pid \(pid.map(String.init) ?? "?")"
        var line = "\(reason) -> \(trackedID) via \(method) switch=\(ms(t2 - t1))"
        if let keyTime { line += " key->done=\(ms(t2 - keyTime))" }
        log(line + " app=\(app)")
        return ok
    }
}

final class Agent {
    let config: Config
    let switcher: Switcher
    private var tap: CFMachPort?
    private var keyIsDown = false
    private var pressSeq = 0
    private var beforePress: TISInputSource?
    private var signalSources: [DispatchSourceSignal] = []
    private var permissionTimer: Timer?

    init(config: Config) {
        self.config = config
        self.switcher = Switcher(config: config)
    }

    func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        log("hantap starting: korean=\(switcher.koreanID) latin=\(InputSources.id(switcher.latin)) hold=\(config.holdMs)ms fallback=\(config.fallback.rawValue)")

        // Never leave CapsLock remapped to a key nobody handles.
        if KeyRemap.isInstalled() { try? KeyRemap.remove() }
        installSignalHandlers()

        if !startTap() {
            log("waiting for Accessibility / Input Monitoring permission (System Settings > Privacy & Security)")
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            _ = CGRequestListenEventAccess()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
                if self?.startTap() == true { t.invalidate() }
            }
        }
        app.run()
        exit(0)
    }

    private func startTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: tapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        do {
            try KeyRemap.install()
        } catch {
            fail("could not remap CapsLock: \(error)")
        }
        log("event tap active, CapsLock remapped to F18")
        return true
    }

    private func installSignalHandlers() {
        for s in [SIGTERM, SIGINT, SIGHUP] {
            signal(s, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: s, queue: .main)
            src.setEventHandler { [weak self] in self?.shutdown(signal: s) }
            src.resume()
            signalSources.append(src)
        }
    }

    private func shutdown(signal: Int32) {
        do { try KeyRemap.remove() } catch { log("could not restore CapsLock: \(error)") }
        log("stopped (signal \(signal)), CapsLock restored")
        exit(0)
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            log("event tap was disabled (\(type.rawValue)), re-enabled")
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_F18) else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyUp {
            keyIsDown = false
            return nil
        }
        guard type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0, !keyIsDown else {
            return nil
        }
        keyIsDown = true
        pressSeq += 1

        if event.flags.contains(.maskShift) {
            CapsLockState.toggle()
            log("shift+capslock -> CapsLock \(CapsLockState.get() == true ? "on" : "off")")
            return nil
        }

        // Switch on key down, synchronously: the tap holds back the keys typed
        // after CapsLock until the focused app has switched.
        let keyTime = NSEvent(cgEvent: event)?.timestamp
        let from = switcher.currentID()
        beforePress = from == switcher.koreanID ? switcher.korean
            : from == InputSources.id(switcher.latin) ? switcher.latin
            : InputSources.find(from)
        switcher.select(switcher.toggleTarget(), reason: "capslock", keyTime: keyTime)

        if config.holdMs > 0 {
            let seq = pressSeq
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(config.holdMs)) { [weak self] in
                guard let self, self.keyIsDown, self.pressSeq == seq else { return }
                self.onHold()
            }
        }
        return nil
    }

    private func onHold() {
        if let beforePress { switcher.select(beforePress, reason: "hold (revert)") }
        CapsLockState.toggle()
        log("hold -> CapsLock \(CapsLockState.get() == true ? "on" : "off")")
    }
}

private let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    return Unmanaged<Agent>.fromOpaque(refcon).takeUnretainedValue().handle(type: type, event: event)
}
