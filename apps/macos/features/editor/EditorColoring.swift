import AppKit

/// Colors a whole text with the editor's syntax highlighting, for views
/// that show code without editing it (the git diff).
public enum EditorColoring {
    @MainActor
    public static func attributed(_ text: String, fileName: String) -> NSAttributedString {
        let look = EditorAppearance.current
        let result = NSMutableAttributedString(string: text, attributes: [.font: look.font, .foregroundColor: look.foreground])
        guard text.utf8.count <= EditorFile.maxHighlightBytes else { return result }
        let syntax = EditorSyntax(fileName: fileName, text: text)
        let length = (text as NSString).length
        for span in syntax.spans(in: NSRange(location: 0, length: length)) where NSMaxRange(span.range) <= length {
            if let color = look.tokens[span.kind] { result.addAttribute(.foregroundColor, value: color, range: span.range) }
        }
        return result
    }
}

/// The same coloring a line at a time, for views that draw only what shows
/// (the review): the syntax tree is kept, the colored text is not. Colored
/// whole, 50 files of the review held 23 MB of runs (heap, make perf, 2026-11-15).
@MainActor
public final class EditorLineColoring {
    private let syntax: EditorSyntax?
    private let text: NSString

    public init(_ text: String, fileName: String) {
        self.text = text as NSString
        syntax = text.utf8.count <= EditorFile.maxHighlightBytes ? EditorSyntax(fileName: fileName, text: text) : nil
    }

    /// The colored text of `range` (UTF-16, of the whole text).
    public func attributed(_ range: NSRange) -> NSAttributedString {
        let look = EditorAppearance.current
        guard NSMaxRange(range) <= text.length else { return NSAttributedString() }
        let piece = NSMutableAttributedString(string: text.substring(with: range), attributes: [.font: look.font, .foregroundColor: look.foreground])
        for span in syntax?.spans(in: range) ?? [] {
            let clipped = NSIntersectionRange(span.range, range)
            guard clipped.length > 0, let color = look.tokens[span.kind] else { continue }
            piece.addAttribute(.foregroundColor, value: color, range: NSRange(location: clipped.location - range.location, length: clipped.length))
        }
        return piece
    }
}
