import AppKit

/// Text input for the terminal: receives composed text from the input system
/// (accents from dead keys, input methods) and sends it to the shell. The
/// composition in progress is kept but not drawn yet.
extension TerminalView: @preconcurrency NSTextInputClient {
    public func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        markedText = NSAttributedString()
        session?.write(text)
    }

    public override func doCommand(by selector: Selector) {
        // Keys with their own meaning were sent by keyDown; ignore the rest
        // instead of beeping.
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        markedText = (string as? NSAttributedString) ?? NSAttributedString(string: (string as? String) ?? "")
    }

    public func unmarkText() {
        markedText = NSAttributedString()
    }

    public func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    public func markedRange() -> NSRange {
        hasMarkedText() ? NSRange(location: 0, length: markedText.length) : NSRange(location: NSNotFound, length: 0)
    }

    public func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    public func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    public func characterIndex(for point: NSPoint) -> Int {
        NSNotFound
    }

    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        // Where the input method shows its candidate window: the view's
        // corner until the cursor position is exposed here.
        window?.convertToScreen(convert(bounds, to: nil)) ?? .zero
    }
}
