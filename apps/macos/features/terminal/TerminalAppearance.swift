import CCadex
import Foundation

/// The colors every terminal draws with: background, text, cursor,
/// selection and the 16 ANSI colors, as 0xRRGGBB. Whoever applies the theme
/// (the app) sets `current`; every TerminalView follows it at once
/// (docs/spec/themes.md). Kept here so the terminal does not depend on the
/// themes feature.
public struct TerminalAppearance: Equatable, Sendable {
    public var background: UInt32
    public var foreground: UInt32
    public var cursor: UInt32
    public var selection: UInt32
    public var ansi: [UInt32]

    public init(background: UInt32, foreground: UInt32, cursor: UInt32, selection: UInt32, ansi: [UInt32]) {
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.selection = selection
        self.ansi = ansi
    }

    /// Posted when `current` changes.
    public static let didChange = Notification.Name("TerminalAppearance.didChange")

    @MainActor public static var current: TerminalAppearance? {
        didSet { NotificationCenter.default.post(name: didChange, object: nil) }
    }

    /// The core's form (cadex_terminal_colors).
    var coreColors: cadex_terminal_colors {
        var colors = cadex_terminal_colors()
        colors.background = background
        colors.foreground = foreground
        colors.cursor = cursor
        withUnsafeMutableBytes(of: &colors.ansi) { raw in
            let slots = raw.bindMemory(to: UInt32.self)
            for (i, value) in ansi.prefix(16).enumerated() { slots[i] = value }
        }
        return colors
    }
}
