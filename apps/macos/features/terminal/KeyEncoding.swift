import AppKit

/// Bytes the shell expects for keys that are not plain text.
///
/// First version, in Swift: covers the keys a shell and full-screen programs
/// need in normal mode, plus Mac-style line editing. Still to move to the
/// core's libghostty-vt key encoder: application cursor mode (DECCKM), other
/// modifier combinations on special keys and the kitty keyboard protocol.
enum KeyEncoding {
    /// Sequence for a special key, or nil if the key is text (letters,
    /// digits, symbols), which goes through the text input system instead so
    /// dead keys and accents compose (´ + e = é on an ABNT2 keyboard).
    static func sequence(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) -> String? {
        if modifiers.contains(.command) {
            return commandEditing[keyCode]
        }
        if modifiers.contains(.option), let editing = optionEditing[keyCode] {
            return editing
        }
        if let special = specialKeys[keyCode] { return special }
        // Control combinations: macOS already maps Ctrl+C to U+0003 and so on.
        if modifiers.contains(.control), let characters, let scalar = characters.unicodeScalars.first,
           scalar.value < 0x20 || scalar.value == 0x7F {
            return characters
        }
        return nil
    }

    // Virtual key codes of the US layout; they name physical keys, so they
    // are the same on every keyboard layout.
    private static let returnKey: UInt16 = 36, keypadEnter: UInt16 = 76, tab: UInt16 = 48
    private static let backspace: UInt16 = 51, escape: UInt16 = 53, forwardDelete: UInt16 = 117
    private static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126
    private static let home: UInt16 = 115, end: UInt16 = 119, pageUp: UInt16 = 116, pageDown: UInt16 = 121

    private static let specialKeys: [UInt16: String] = [
        returnKey: "\r",
        keypadEnter: "\r",
        tab: "\t",
        backspace: "\u{7F}",
        escape: "\u{1B}",
        forwardDelete: "\u{1B}[3~",
        left: "\u{1B}[D",
        right: "\u{1B}[C",
        down: "\u{1B}[B",
        up: "\u{1B}[A",
        home: "\u{1B}[H",
        end: "\u{1B}[F",
        pageUp: "\u{1B}[5~",
        pageDown: "\u{1B}[6~",
    ]

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
