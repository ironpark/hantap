import Foundation

/// CapsLock -> F18 at the HID event system (hidutil UserKeyMapping), so the
/// system never sees CapsLock: no built-in CapsLock delay, no built-in
/// CapsLock input switching. Other mappings already present are kept.
enum KeyRemap {
    static let capsLock: Int64 = 0x7_0000_0039
    static let f18: Int64 = 0x7_0000_006D
    private static let srcKey = "HIDKeyboardModifierMappingSrc"
    private static let dstKey = "HIDKeyboardModifierMappingDst"

    static func install() throws {
        var m = try current().filter { $0[srcKey] != capsLock }
        m.append([srcKey: capsLock, dstKey: f18])
        try set(m)
    }

    static func remove() throws {
        let m = try current().filter { !($0[srcKey] == capsLock && $0[dstKey] == f18) }
        try set(m)
    }

    static func isInstalled() -> Bool {
        (try? current().contains { $0[srcKey] == capsLock && $0[dstKey] == f18 }) ?? false
    }

    static func current() throws -> [[String: Int64]] {
        let out = try hidutil(["property", "--get", "UserKeyMapping"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if out.isEmpty || out == "(null)" { return [] }
        // hidutil prints an OpenStep-style plist; its numbers come back as strings.
        guard let list = try PropertyListSerialization.propertyList(from: Data(out.utf8), format: nil) as? [[String: Any]] else {
            throw RemapError("unexpected hidutil output: \(out)")
        }
        return list.map { entry in
            entry.compactMapValues { v -> Int64? in
                if let n = v as? NSNumber { return n.int64Value }
                if let s = v as? String { return Int64(s) }
                return nil
            }
        }
    }

    private static func set(_ mapping: [[String: Int64]]) throws {
        let json = try JSONSerialization.data(withJSONObject: ["UserKeyMapping": mapping])
        _ = try hidutil(["property", "--set", String(decoding: json, as: UTF8.self)])
    }

    private static func hidutil(_ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(decoding: data, as: UTF8.self)
        guard p.terminationStatus == 0 else { throw RemapError("hidutil \(args.joined(separator: " ")): \(out)") }
        return out
    }
}

struct RemapError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}
