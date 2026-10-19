import AppKit
import CCadex

/// How every editor looks: font and colors, filled by the app from the
/// theme and the terminal font (this feature does not depend on themes).
public struct EditorAppearance: Equatable {
    public var font: NSFont
    public var background: NSColor
    public var foreground: NSColor
    public var currentLine: NSColor
    public var lineNumber: NSColor
    public var selection: NSColor
    /// Color of each CADEX_TOKEN_* kind; missing kinds use the foreground.
    public var tokens: [UInt8: NSColor]

    public init(font: NSFont, background: NSColor, foreground: NSColor, currentLine: NSColor,
                lineNumber: NSColor, selection: NSColor, tokens: [UInt8: NSColor]) {
        self.font = font
        self.background = background
        self.foreground = foreground
        self.currentLine = currentLine
        self.lineNumber = lineNumber
        self.selection = selection
        self.tokens = tokens
    }

    /// The token colors from a terminal palette (the 16 ANSI colors, as
    /// 0xRRGGBB): editors of the same theme look like its terminal.
    public static func tokens(ansi: [UInt32], foreground: UInt32) -> [UInt8: NSColor] {
        func color(_ i: Int) -> NSColor { rgb(i < ansi.count ? ansi[i] : foreground) }
        return [
            UInt8(CADEX_TOKEN_KEYWORD): color(5), UInt8(CADEX_TOKEN_STRING): color(2),
            UInt8(CADEX_TOKEN_NUMBER): color(3), UInt8(CADEX_TOKEN_COMMENT): color(8),
            UInt8(CADEX_TOKEN_FUNCTION): color(4), UInt8(CADEX_TOKEN_TYPE): color(6),
            UInt8(CADEX_TOKEN_CONSTANT): color(11), UInt8(CADEX_TOKEN_PROPERTY): color(14),
            UInt8(CADEX_TOKEN_OPERATOR): rgb(foreground), UInt8(CADEX_TOKEN_PUNCTUATION): rgb(foreground).withAlphaComponent(0.7),
            UInt8(CADEX_TOKEN_VARIABLE): color(1), UInt8(CADEX_TOKEN_TAG): color(1),
            UInt8(CADEX_TOKEN_ATTRIBUTE): color(3), UInt8(CADEX_TOKEN_ESCAPE): color(6),
            UInt8(CADEX_TOKEN_HEADING): color(4), UInt8(CADEX_TOKEN_LINK): color(12),
            UInt8(CADEX_TOKEN_EMPHASIS): color(13),
        ]
    }

    static func rgb(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// What open editors use; setting it restyles them.
    @MainActor public static var current = EditorAppearance(
        font: .monospacedSystemFont(ofSize: 13, weight: .regular), background: .textBackgroundColor,
        foreground: .textColor, currentLine: .quaternaryLabelColor, lineNumber: .tertiaryLabelColor,
        selection: .selectedTextBackgroundColor, tokens: [:]
    ) {
        didSet {
            if current != oldValue { NotificationCenter.default.post(name: didChange, object: nil) }
        }
    }

    public static let didChange = Notification.Name("CadexEditorAppearanceDidChange")
}
