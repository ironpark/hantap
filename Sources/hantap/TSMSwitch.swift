import AppKit
import Carbon

// Selects an input source the way the Input menu does: the app that has
// keyboard focus is asked to switch through its Text Services Manager port
// (message 7), instead of TISSelectInputSource committing the change
// system-wide first and notifying the app afterwards. That ordering is what
// leaves non-native apps (Electron, Java, ...) typing in the old input source
// until focus changes. Adapted from laishulu/macism TSMUtils.swift
// (MIT, Copyright (c) 2023 https://github.com/laishulu; see THIRD_PARTY_NOTICES).
//
// The symbols are private and resolved at run time; when any is missing the
// caller falls back to TISSelectInputSource.

private let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

private func sym<T>(_ name: String, _: T.Type) -> T? {
    dlsym(rtldDefault, name).map { unsafeBitCast($0, to: T.self) }
}

private typealias KeyFocusFn = @convention(c) (
    UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<DarwinBoolean>
) -> Int32
private typealias PSNToPIDFn = @convention(c) (
    UnsafePointer<ProcessSerialNumber>, UnsafeMutablePointer<pid_t>
) -> OSStatus
private typealias RemotePortFn = @convention(c) (
    CFAllocator?, CFString, pid_t
) -> Unmanaged<CFMessagePort>?
private typealias FlattenFn = @convention(c) (
    TISInputSource, UnsafeMutablePointer<Unmanaged<AnyObject>?>
) -> DarwinBoolean

enum SwitchResult {
    case tsm(pid: pid_t)
    case failed(String)
}

final class TSMSwitch {
    private let keyFocus = sym("CPSGetKeyFocusProcess", KeyFocusFn.self)
    private let psnToPID = sym("GetProcessPID", PSNToPIDFn.self)
    private let remotePort = sym("CFMessagePortCreatePerProcessRemote", RemotePortFn.self)
    private let flatten = sym("_CreateFlattenedInputSource", FlattenFn.self)

    private var ports: [pid_t: CFMessagePort] = [:]
    private var requests: [String: CFData] = [:]

    /// Only our reply port is scheduled in this mode, so waiting for the reply
    /// never re-enters the event tap (which lives in the common modes).
    private let replyMode = "dev.hantap.tsm" as CFString
    private let timeout: CFTimeInterval = 0.3

    var available: Bool {
        keyFocus != nil && psnToPID != nil && remotePort != nil && flatten != nil
    }

    /// The process that receives key events. Not always the frontmost app:
    /// a non-activating panel (Spotlight, Raycast) can have keyboard focus.
    func keyFocusPID() -> pid_t? {
        guard let keyFocus, let psnToPID else { return nil }
        var psn = ProcessSerialNumber()
        var ignored: DarwinBoolean = false
        var pid: pid_t = -1
        guard keyFocus(&psn, &ignored) == 0, psnToPID(&psn, &pid) == noErr, pid > 0 else { return nil }
        return pid
    }

    /// Synchronous: when this returns .tsm the focused app has switched, so the
    /// keys typed next go to the new input method.
    func select(_ source: TISInputSource) -> SwitchResult {
        guard available else { return .failed("private symbols missing") }
        guard let pid = keyFocusPID() else { return .failed("no key focus process") }
        if pid == getpid() { return .failed("key focus is hantap") }
        guard let data = request(for: source) else { return .failed("flatten failed") }

        // A cached port goes stale when the app quits or its TSM context is
        // recreated; retry once with a fresh one.
        for attempt in 0..<2 {
            guard let port = port(for: pid, fresh: attempt > 0) else { return .failed("no TSM port (pid \(pid))") }
            var reply: Unmanaged<CFData>?
            let status = CFMessagePortSendRequest(port, 7, data, timeout, timeout, replyMode, &reply)
            if status == kCFMessagePortSuccess {
                if let replyData = reply?.takeRetainedValue(),
                   let dict = CFPropertyListCreateWithData(nil, replyData, 0, nil, nil)?.takeRetainedValue() as? [String: Any],
                   let err = dict["tsmInputModeReplyToServerErrorKey"] as? Int, err != 0 {
                    return .failed("app replied error \(err)")
                }
                return .tsm(pid: pid)
            }
            ports[pid] = nil
            if status == kCFMessagePortIsInvalid && attempt == 0 { continue }
            return .failed(status == kCFMessagePortSendTimeout || status == kCFMessagePortReceiveTimeout
                           ? "app did not answer in \(Int(timeout * 1000))ms" : "send status \(status)")
        }
        return .failed("port invalid")
    }

    private func port(for pid: pid_t, fresh: Bool) -> CFMessagePort? {
        if !fresh, let p = ports[pid], CFMessagePortIsValid(p) { return p }
        guard let remotePort,
              let p = remotePort(nil, "com.apple.tsm.portname" as CFString, pid)?.takeRetainedValue()
        else { return nil }
        if ports.count > 32 { ports.removeAll() }
        ports[pid] = p
        return p
    }

    private func request(for source: TISInputSource) -> CFData? {
        let id = InputSources.id(source)
        if let cached = requests[id] { return cached }
        guard let flatten else { return nil }
        var flatRef: Unmanaged<AnyObject>?
        guard flatten(source, &flatRef).boolValue, let flat = flatRef?.takeRetainedValue() else { return nil }
        let dict = ["tsmInputSourceSelectedInpSrcKey": flat] as CFDictionary
        guard let data = CFPropertyListCreateData(nil, dict, .xmlFormat_v1_0, 0, nil)?.takeRetainedValue() else { return nil }
        requests[id] = data
        return data
    }
}
