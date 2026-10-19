import Foundation

/// Every user preference, as saved in settings.json (docs/spec/settings.md).
/// One file, one place: terminal, appearance and shortcuts all live here.
public struct Settings: Equatable, Sendable {
    public struct General: Equatable, Sendable {
        /// Empty: the system's shell.
        public var shell = ""
        public var confirmClose = true
        public var confirmMultilinePaste = true
    }

    public struct Terminal: Equatable, Sendable {
        public var fontFamily = "SF Mono"
        public var fontSize: Double = 13
        /// "bar", "block" or "underline".
        public var cursor = "bar"
        public var cursorBlink = false
        public var historyLines = 10_000
        public var optionAsMeta = false
        public var copyOnSelect = false
    }

    public struct Appearance: Equatable, Sendable {
        /// The theme family id ("caffeine").
        public var theme = "caffeine"
        /// "system", "dark" or "light".
        public var mode = "system"
        public var vibrancy = false
        /// A path, or nil for no background image.
        public var backgroundImage: String?
        public var backgroundOpacity: Double = 0.5
        public var backgroundBlur: Double = 0
    }

    public struct Explorer: Equatable, Sendable {
        /// Names starting with "." in the tree, dimmed (docs/spec/explorer.md).
        public var showHidden = true
    }

    public var general = General()
    public var terminal = Terminal()
    public var appearance = Appearance()
    public var explorer = Explorer()
    /// "cmd+shift+t" → command id, or nil to turn a default off.
    public var shortcuts: [String: String?] = [:]

    public init() {}

    // Limits from docs/spec/settings.md.
    static let fontSizes = 8.0...32.0
    static let historyRange = 100...100_000
    static let cursors = ["bar", "block", "underline"]
    static let modes = ["system", "dark", "light"]
}
