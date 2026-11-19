import Carbon

enum InputSources {
    /// Enabled input sources that can be selected (what the Input menu lists).
    static func enabled() -> [TISInputSource] {
        let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
        return list.filter { isSelectable($0) && category($0) == (kTISCategoryKeyboardInputSource as String) }
    }

    static func find(_ id: String) -> TISInputSource? {
        enabled().first { self.id($0) == id }
    }

    static func current() -> TISInputSource {
        TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    }

    static func currentID() -> String { id(current()) }

    static func id(_ s: TISInputSource) -> String {
        property(s, kTISPropertyInputSourceID) as? String ?? "?"
    }

    static func languages(_ s: TISInputSource) -> [String] {
        property(s, kTISPropertyInputSourceLanguages) as? [String] ?? []
    }

    static func isSelectable(_ s: TISInputSource) -> Bool {
        property(s, kTISPropertyInputSourceIsSelectCapable) as? Bool ?? false
    }

    static func category(_ s: TISInputSource) -> String {
        property(s, kTISPropertyInputSourceCategory) as? String ?? ""
    }

    static func isCJKV(_ s: TISInputSource) -> Bool {
        guard let lang = languages(s).first else { return false }
        return lang == "ko" || lang == "ja" || lang == "vi" || lang.hasPrefix("zh")
    }

    private static func property(_ s: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let p = TISGetInputSourceProperty(s, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue()
    }

    /// Picks the Korean and Latin sources to toggle between: explicit IDs win,
    /// otherwise the first enabled source whose primary language is ko / not CJKV.
    static func resolvePair(korean: String?, latin: String?) -> (korean: TISInputSource, latin: TISInputSource)? {
        let all = enabled()
        let ko = korean.flatMap { want in all.first { id($0) == want } }
            ?? all.first { id($0) == "com.apple.inputmethod.Korean.2SetKorean" }
            ?? all.first { languages($0).first == "ko" && id($0).contains(".Korean.") }
            ?? all.first { languages($0).first == "ko" }
        let la = latin.flatMap { want in all.first { id($0) == want } }
            ?? all.first { id($0) == "com.apple.keylayout.ABC" }
            ?? all.first { !isCJKV($0) }
        guard let ko, let la else { return nil }
        return (ko, la)
    }
}
