import AppKit

/// A theme (docs/spec/themes.md): the colors of the interface and of the
/// terminal. Colors are 0xRRGGBB plus an alpha where it matters.
public struct Theme: Equatable, Sendable {
    public struct Interface: Equatable, Sendable {
        /// Title bar, the gaps between panels, status bar.
        public var chrome: RGB
        /// The rounded panels: sidebar and terminal area.
        public var panel: RGB
        public var panelBorder: RGB
        public var tabActive: RGB
        public var field: RGB
        public var text: RGB
        public var secondaryText: RGB
        public var accent: RGB
    }

    public struct Terminal: Equatable, Sendable {
        public var background: RGB
        public var foreground: RGB
        public var cursor: RGB
        /// The selection tint over the text.
        public var selection: RGB
        /// The 16 ANSI colors: black, red, green, yellow, blue, magenta,
        /// cyan, white, then their bright versions.
        public var ansi: [RGB]
    }

    public var name: String
    public var dark: Bool
    public var interface: Interface
    public var terminal: Terminal
}

/// A color as 0xRRGGBB, the form the core and the theme files use.
public struct RGB: Equatable, Hashable, Sendable {
    public var value: UInt32

    public init(_ value: UInt32) {
        self.value = value & 0xFFFFFF
    }

    public var nsColor: NSColor { color(alpha: 1) }

    public func color(alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
    }

    /// "#1E1E1E"
    public var hex: String { String(format: "#%06X", value) }

    /// This color moved a fraction `t` toward `other`.
    public func mixed(_ other: RGB, _ t: Double) -> RGB {
        func channel(_ shift: UInt32) -> UInt32 {
            let a = Double((value >> shift) & 0xFF), b = Double((other.value >> shift) & 0xFF)
            return UInt32((a + (b - a) * t).rounded()) << shift
        }
        return RGB(channel(16) | channel(8) | channel(0))
    }

    /// WCAG relative luminance, 0 (black) to 1 (white).
    public var luminance: Double {
        func linear(_ shift: UInt32) -> Double {
            let c = Double((value >> shift) & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
    }

    /// WCAG contrast ratio with `other`, 1 to 21.
    public func contrast(with other: RGB) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

public extension Theme {
    /// The frame on the terminal's ground: the window, the sidebar and each pane's box take the
    /// terminal's background, as Cadex Night's mockups do (chrome == terminal). The catalogs gave
    /// many themes a frame a shade off the terminal (GitHub Light: #F6F8FA around #FFFFFF), and
    /// the terminal showed as a box framed in the middle of the window (owner, 2026-11-18).
    func onTerminalGround() -> Theme {
        var theme = self
        guard theme.interface.chrome != terminal.background else { return theme }
        let accent = theme.interface.accent
        theme.interface.chrome = terminal.background
        theme.interface.tabActive = terminal.background.mixed(accent, 0.22)
        return theme
    }
}
