import AppKit

/// The user's terminal preferences (docs/spec/settings.md): font, cursor,
/// history, keyboard and the questions before pasting or closing. Whoever
/// owns the settings file (the app) sets `current`; every TerminalView
/// follows it at once. A "não perguntar de novo" in an alert changes it
/// here, and the app saves it. Kept in this feature so it does not depend on
/// the settings feature.
public struct TerminalPreferences: Equatable, Sendable {
    public enum CursorShape: UInt8, Sendable, CaseIterable {
        case block = 0, bar = 1, underline = 2
    }

    /// Empty: the system's shell ($SHELL, then zsh).
    public var shell = ""
    public var fontFamily = "SF Mono"
    public var fontSize: CGFloat = 13
    public var cursorShape = CursorShape.bar
    public var cursorBlink = false
    /// Read when a terminal opens; changing it affects new terminals.
    public var historyLines = 10_000
    public var optionAsMeta = false
    public var copyOnSelect = false
    public var confirmMultilinePaste = true
    public var confirmClose = true
    /// The WCAG ratio text keeps against its background (terminal.minimumContrast);
    /// 1 leaves the colors as the program sent them (plan 15, phase C).
    public var minimumContrast: Double = 1
    /// Line height as a multiple of the font's (terminal.lineHeight).
    public var lineHeight: Double = 1
    /// Extra space between letters, in points; may be negative (terminal.letterSpacing).
    public var letterSpacing: Double = 0
    /// OpenType features of the font, "-" turning one off: "calt", "liga"
    /// (ligatures), "ss01", "zero" (terminal.fontFeatures).
    public var fontFeatures: [String] = []

    public init() {}

    /// What the font is made from: a change here redraws every glyph; any
    /// other change does not.
    var fontKey: [String] {
        [fontFamily, "\(fontSize)", "\(lineHeight)", "\(letterSpacing)"] + fontFeatures
    }

    /// Posted when `current` changes.
    public static let didChange = Notification.Name("TerminalPreferences.didChange")

    @MainActor public static var current = TerminalPreferences() {
        didSet {
            if current != oldValue { NotificationCenter.default.post(name: didChange, object: nil) }
        }
    }
}
