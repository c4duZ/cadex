import AppKit

/// The interface's zoom, density and font, apart from the terminal's
/// (plan 15, phase D: appearance.uiZoom, appearance.density, appearance.uiFont,
/// appearance.uiFontSize, like Zed).
///
/// Views read these when they are built. Like the language, they apply when
/// Cadex opens: the app calls `configure` once before any view exists, and
/// the settings window offers "Reopen now". Re-laying out every view live was
/// not worth the code (owner's decision, 2026-10-20).
///
/// Every size in the code is the design size at zoom 1, normal density and
/// the system font at 13 pt, so someone who never touches these sees the app
/// exactly as before.
@MainActor
public enum UILooks {
    public static let zoomRange: ClosedRange<CGFloat> = 0.8...1.5
    /// The base size the design was drawn at.
    public static let designFontSize: CGFloat = 13
    public static let fontSizeRange: ClosedRange<CGFloat> = 9...24
    /// Vertical spacing in compact density: 15% tighter, about what Zed's
    /// compact mode takes off a row.
    public static let compactFactor: CGFloat = 0.85

    public private(set) static var zoom: CGFloat = 1
    public private(set) static var compact = false
    /// Empty means the system font.
    public private(set) static var fontFamily = ""
    public private(set) static var fontSize: CGFloat = designFontSize

    /// Once at launch, before any view is made. Out-of-range values are
    /// clamped: a hand-edited settings.json must not make the app unusable.
    public static func configure(zoom: CGFloat, compact: Bool, fontFamily: String, fontSize: CGFloat) {
        self.zoom = min(max(zoom, zoomRange.lowerBound), zoomRange.upperBound)
        self.compact = compact
        self.fontFamily = fontFamily.trimmingCharacters(in: .whitespaces)
        self.fontSize = min(max(fontSize, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    /// How much a design font size grows: the zoom times the chosen base size.
    public static var fontScale: CGFloat { zoom * fontSize / designFontSize }

    /// The interface font at a design size: in the chosen family with the
    /// same weight, or the system font when none is set or it is missing.
    public static func font(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let scaled = size * fontScale
        if !fontFamily.isEmpty, let font = familyFont(scaled, weight: weight) { return font }
        return .systemFont(ofSize: scaled, weight: weight)
    }

    /// Short codes in the interface (a sha, a status letter): scaled like the
    /// rest, always the system's monospaced font so columns still line up.
    public static func monospaced(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size * fontScale, weight: weight)
    }

    /// Counts and dates in columns: digits of equal width.
    public static func monospacedDigits(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedDigitSystemFont(ofSize: size * fontScale, weight: weight)
    }

    /// A width, padding or icon size, scaled by the zoom.
    public static func pt(_ value: CGFloat) -> CGFloat { value * zoom }

    /// A height (a row, a bar): scaled by the zoom and tightened when
    /// compact. Whole points, so lines between rows stay crisp; the design
    /// heights are whole, so zoom 1 gives them back unchanged.
    public static func rowHeight(_ value: CGFloat) -> CGFloat {
        (value * zoom * (compact ? compactFactor : 1)).rounded()
    }

    private static func familyFont(_ size: CGFloat, weight: NSFont.Weight) -> NSFont? {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: fontFamily, .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue],
        ])
        // A missing family comes back as some other font: only keep a match.
        guard let font = NSFont(descriptor: descriptor, size: size), font.familyName == fontFamily else { return nil }
        return font
    }
}
