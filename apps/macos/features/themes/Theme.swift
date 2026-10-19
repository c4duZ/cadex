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
}
