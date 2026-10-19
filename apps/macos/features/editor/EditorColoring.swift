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
