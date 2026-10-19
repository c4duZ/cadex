import AppKit
import CCadex

/// Decides where a key press goes. The core encodes every key a program
/// reads (cadex_terminal_key, which follows the program's modes); this file
/// only maps macOS key codes to the core's keys, plus Mac-style line editing,
/// which is a convention of the app and not of the terminal.
enum KeyEncoding {
    enum Route: Equatable {
        /// Mac-style line editing: these bytes go to the shell as they are.
        case macEditing(String)
        /// A key for the core's encoder: CADEX_KEY_* (NONE for text with
        /// Ctrl or Meta) and CADEX_MOD_*.
        case core(key: UInt16, mods: UInt8)
        /// Plain text: through the input system, so dead keys and accents
        /// compose (´ + e = é on an ABNT2 keyboard).
        case text
    }

    /// optionAsMeta: the left Option acts as Meta (Alt) instead of typing the
    /// macOS special characters (docs/spec/terminal.md, Teclado).
    static func route(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, optionAsMeta: Bool) -> Route {
        if let editing = macEditing(keyCode: keyCode, modifiers: modifiers) {
            return .macEditing(editing)
        }
        let meta = optionAsMeta && isLeftOption(modifiers)
        let mods = coreMods(modifiers, meta: meta)
        if let key = coreKeys[keyCode] {
            return .core(key: key, mods: mods)
        }
        if modifiers.contains(.control) || meta {
            return .core(key: UInt16(CADEX_KEY_NONE), mods: mods)
        }
        return .text
    }

    /// CADEX_MOD_* bits. Option counts as Alt only when it acts as Meta;
    /// otherwise it already chose the character.
    static func coreMods(_ modifiers: NSEvent.ModifierFlags, meta: Bool) -> UInt8 {
        var mods: UInt32 = 0
        if modifiers.contains(.shift) { mods |= CADEX_MOD_SHIFT }
        if modifiers.contains(.control) { mods |= CADEX_MOD_CTRL }
        if meta { mods |= CADEX_MOD_ALT }
        if modifiers.contains(.command) { mods |= CADEX_MOD_SUPER }
        return UInt8(mods)
    }

    /// NX_DEVICELALTKEYMASK (IOKit's IOLLEvent.h): the device-dependent bit
    /// of the left Option key, which NSEvent.ModifierFlags does not name.
    private static let leftOptionMask: UInt = 0x20

    static func isLeftOption(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.contains(.option) && modifiers.rawValue & leftOptionMask != 0
    }

    private static func macEditing(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String? {
        if modifiers.contains(.command) { return commandEditing[keyCode] }
        if modifiers.contains(.option) { return optionEditing[keyCode] }
        return nil
    }

    // Virtual key codes of the US layout; they name physical keys, so they
    // are the same on every keyboard layout.
    private static let returnKey: UInt16 = 36, keypadEnter: UInt16 = 76, tab: UInt16 = 48
    private static let backspace: UInt16 = 51, escape: UInt16 = 53, forwardDelete: UInt16 = 117
    private static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
    private static let home: UInt16 = 115, end: UInt16 = 119, pageUp: UInt16 = 116, pageDown: UInt16 = 121
    /// The Help key of older Apple keyboards sits where Insert is on a PC one.
    private static let help: UInt16 = 114
    private static let functionKeys: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

    private static let coreKeys: [UInt16: UInt16] = {
        var keys: [UInt16: Int32] = [
            returnKey: CADEX_KEY_ENTER,
            keypadEnter: CADEX_KEY_ENTER,
            tab: CADEX_KEY_TAB,
            backspace: CADEX_KEY_BACKSPACE,
            escape: CADEX_KEY_ESCAPE,
            forwardDelete: CADEX_KEY_DELETE,
            help: CADEX_KEY_INSERT,
            home: CADEX_KEY_HOME,
            end: CADEX_KEY_END,
            pageUp: CADEX_KEY_PAGE_UP,
            pageDown: CADEX_KEY_PAGE_DOWN,
            up: CADEX_KEY_UP,
            down: CADEX_KEY_DOWN,
            left: CADEX_KEY_LEFT,
            right: CADEX_KEY_RIGHT,
        ]
        for (index, code) in functionKeys.enumerated() {
            keys[code] = CADEX_KEY_F1 + Int32(index)
        }
        return keys.mapValues { UInt16($0) }
    }()

    /// Mac-style editing with Option: move and delete by word. These are the
    /// readline/zle bindings every common shell has (Meta+b, Meta+f, ...).
    private static let optionEditing: [UInt16: String] = [
        left: "\u{1B}b",
        right: "\u{1B}f",
        backspace: "\u{1B}\u{7F}",
        forwardDelete: "\u{1B}d",
    ]

    /// Mac-style editing with Command: jump to and delete to the ends of the
    /// line (Ctrl+A, Ctrl+E, Ctrl+U, Ctrl+K in the shell).
    private static let commandEditing: [UInt16: String] = [
        left: "\u{01}",
        right: "\u{05}",
        backspace: "\u{15}",
        forwardDelete: "\u{0B}",
    ]
}
