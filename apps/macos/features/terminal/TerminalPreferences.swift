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

    public init() {}

    /// Posted when `current` changes.
    public static let didChange = Notification.Name("TerminalPreferences.didChange")

    @MainActor public static var current = TerminalPreferences() {
        didSet {
            if current != oldValue { NotificationCenter.default.post(name: didChange, object: nil) }
        }
    }
}
