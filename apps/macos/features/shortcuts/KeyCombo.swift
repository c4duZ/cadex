import AppKit
import Strings

/// A key combination: "cmd+shift+d", ⌘⇧D. The key is the character the
/// keyboard layout gives without modifiers (so ⌘[ follows the layout, as
/// macOS menus do) or a named key: left, right, up, down, tab, return,
/// escape, delete, space.
public struct KeyCombo: Hashable, Sendable, CustomStringConvertible {
    public var key: String
    public var command = false
    public var shift = false
    public var option = false
    public var control = false

    public init(key: String, command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key.lowercased()
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    /// Parses "cmd+shift+t", "ctrl+tab", "cmd+opt+left". Nil when malformed.
    public init?(_ text: String) {
        var parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        // "cmd++" is cmd and the plus key.
        if text.hasSuffix("++") { parts = Array(parts.dropLast(2)) + ["+"] }
        guard let key = parts.popLast(), !key.isEmpty else { return nil }
        self.init(key: key)
        for modifier in parts {
            switch modifier {
            case "cmd", "command": command = true
            case "shift": shift = true
            case "opt", "option", "alt": option = true
            case "ctrl", "control": control = true
            default: return nil
            }
        }
        guard key.count == 1 || Self.namedKeys.values.contains(key) else { return nil }
    }

    /// The combination of a key press, or nil for a press without a usable
    /// key (a lone modifier, a dead key).
    public init?(event: NSEvent) {
        let flags = event.modifierFlags
        let key: String
        if let named = Self.namedKeys[event.keyCode] {
            key = named
        } else {
            guard let plain = event.characters(byApplyingModifiers: []), plain.count == 1 else { return nil }
            key = plain
        }
        self.init(key: key, command: flags.contains(.command), shift: flags.contains(.shift),
                  option: flags.contains(.option), control: flags.contains(.control))
    }

    /// "cmd+shift+t": the form of the preferences file.
    public var description: String {
        var parts: [String] = []
        if control { parts.append("ctrl") }
        if option { parts.append("opt") }
        if shift { parts.append("shift") }
        if command { parts.append("cmd") }
        return (parts + [key]).joined(separator: "+")
    }

    /// "⌃⌥⇧⌘T", in the order macOS menus use.
    public var label: String {
        var text = ""
        if control { text += "⌃" }
        if option { text += "⌥" }
        if shift { text += "⇧" }
        if command { text += "⌘" }
        return text + (Self.symbols[key] ?? key.uppercased())
    }

    /// For NSMenuItem: the key equivalent and its modifier mask.
    public var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags) {
        var mask: NSEvent.ModifierFlags = []
        if command { mask.insert(.command) }
        if shift { mask.insert(.shift) }
        if option { mask.insert(.option) }
        if control { mask.insert(.control) }
        return (Self.menuKeys[key] ?? key, mask)
    }

    /// Ctrl with a letter or symbol and nothing else but Shift: the keys
    /// programs in the terminal use (Ctrl+B, Ctrl+R...). The app never takes
    /// them (docs/spec/shortcuts.md). Ctrl+Tab is not one: shells do not use it.
    public var isTerminalControlKey: Bool {
        control && !command && !option && key.count == 1
    }

    // Virtual key codes (US layout names; same physical keys everywhere).
    private static let namedKeys: [UInt16: String] = [
        123: "left", 124: "right", 125: "down", 126: "up", 48: "tab", 36: "return",
        76: "return", 53: "escape", 51: "delete", 49: "space",
    ]

    private static let symbols: [String: String] = [
        "left": "←", "right": "→", "up": "↑", "down": "↓", "tab": "⇥", "return": "↩",
        "escape": "⎋", "delete": "⌫", "space": T("Space", "Espaço"),
    ]

    private static let menuKeys: [String: String] = [
        "left": String(UnicodeScalar(NSLeftArrowFunctionKey)!), "right": String(UnicodeScalar(NSRightArrowFunctionKey)!),
        "up": String(UnicodeScalar(NSUpArrowFunctionKey)!), "down": String(UnicodeScalar(NSDownArrowFunctionKey)!),
        "tab": "\t", "return": "\r", "escape": "\u{1B}", "delete": "\u{8}", "space": " ",
    ]
}
