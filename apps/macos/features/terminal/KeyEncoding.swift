import AppKit

/// Bytes the shell expects for keys that are not plain text.
///
/// First version, in Swift: covers the keys a shell and full-screen programs
/// need in normal mode. Still to move to the core's libghostty-vt key
/// encoder: application cursor mode (DECCKM), modifier combinations on
/// special keys and the kitty keyboard protocol.
enum KeyEncoding {
    /// Sequence for a special key, or nil if the key is text (letters,
    /// digits, symbols), which goes through the text input system instead so
    /// dead keys and accents compose (´ + e = é on an ABNT2 keyboard).
    static func sequence(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) -> String? {
        if let special = specialKeys[keyCode] { return special }
        // Control combinations: macOS already maps Ctrl+C to U+0003 and so on.
        if modifiers.contains(.control), let characters, let scalar = characters.unicodeScalars.first,
           scalar.value < 0x20 || scalar.value == 0x7F {
            return characters
        }
        return nil
    }

    /// Virtual key codes of the US layout; they name physical keys, so they
    /// are the same on every keyboard layout.
    private static let specialKeys: [UInt16: String] = [
        36: "\r",          // Return
        76: "\r",          // keypad Enter
        48: "\t",          // Tab
        51: "\u{7F}",      // Backspace
        53: "\u{1B}",      // Escape
        117: "\u{1B}[3~",  // forward Delete
        123: "\u{1B}[D",   // Left
        124: "\u{1B}[C",   // Right
        125: "\u{1B}[B",   // Down
        126: "\u{1B}[A",   // Up
        115: "\u{1B}[H",   // Home
        119: "\u{1B}[F",   // End
        116: "\u{1B}[5~",  // Page Up
        121: "\u{1B}[6~",  // Page Down
    ]
}
