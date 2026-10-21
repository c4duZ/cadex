import AppKit
import CoreText

/// Size of one terminal cell and where text sits in it, in device pixels.
/// Everything is a whole number of pixels so glyphs never land between
/// pixels: that is what keeps the text crisp (docs/spec/terminal.md).
struct CellMetrics: Equatable {
    var width: Int
    var height: Int
    /// Distance from the top of the cell to the text baseline.
    var baseline: Int
    var underlineOffset: Int
    var lineThickness: Int
    /// Device pixels per point (2 on Retina).
    var scale: CGFloat
    /// Where a glyph starts inside its cell: half the letter spacing, so
    /// the letters stay centered in wider (or narrower) cells.
    var glyphOffset = 0
    /// The font's own advance; the cell is wider by the letter spacing.
    var advance = 0
}

/// How the terminal's text is set (plan 15, phase C): line height as a
/// multiple of the font's, extra space between letters in points, and the
/// OpenType features ("calt", "ss01", "-liga", "zero").
struct Typesetting: Equatable {
    var lineHeight: CGFloat = 1
    var letterSpacing: CGFloat = 0
    var features: [String] = []

    /// "calt" or "liga" on: neighbouring symbols are set together, so
    /// "->" can become one arrow across two cells.
    var joinsLetters: Bool { features.contains("calt") || features.contains("liga") }
}

/// The terminal font (SF Mono 13 pt by default) in its four styles, sized
/// in device pixels for one display scale.
final class TerminalFont {
    static let defaultPointSize: CGFloat = 13

    let metrics: CellMetrics
    let typesetting: Typesetting
    private let regular: CTFont
    private let bold: CTFont
    private let italic: CTFont
    private let boldItalic: CTFont

    /// family: a font installed on the system; "SF Mono", or one that is
    /// missing, uses the system's monospaced font (docs/spec/settings.md).
    init(family: String = "SF Mono", pointSize: CGFloat = TerminalFont.defaultPointSize, scale: CGFloat,
         typesetting: Typesetting = Typesetting()) {
        let pixelSize = pointSize * scale
        self.typesetting = typesetting
        let plain: CTFont, heavy: CTFont
        if family != "SF Mono", let custom = NSFont(name: family, size: pixelSize) {
            plain = custom as CTFont
            heavy = (NSFontManager.shared.convert(custom, toHaveTrait: .boldFontMask)) as CTFont
        } else {
            // monospacedSystemFont is SF Mono, which ships with macOS.
            plain = NSFont.monospacedSystemFont(ofSize: pixelSize, weight: .regular) as CTFont
            heavy = NSFont.monospacedSystemFont(ofSize: pixelSize, weight: .bold) as CTFont
        }
        regular = Self.withFeatures(plain, typesetting.features)
        bold = Self.withFeatures(heavy, typesetting.features)
        italic = Self.italicVariant(of: regular)
        boldItalic = Self.italicVariant(of: bold)
        metrics = Self.measure(regular, scale: scale, typesetting: typesetting)
    }

    /// The font with OpenType features on ("ss01") or off ("-liga").
    private static func withFeatures(_ font: CTFont, _ features: [String]) -> CTFont {
        guard !features.isEmpty else { return font }
        let settings = features.map { feature -> [CFString: Any] in
            let off = feature.hasPrefix("-")
            return [kCTFontOpenTypeFeatureTag: String(feature.dropFirst(off ? 1 : 0)), kCTFontOpenTypeFeatureValue: off ? 0 : 1]
        }
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFeatureSettingsAttribute: settings] as CFDictionary)
        return CTFontCreateCopyWithAttributes(font, 0, nil, descriptor)
    }

    func font(bold isBold: Bool, italic isItalic: Bool) -> CTFont {
        switch (isBold, isItalic) {
        case (false, false): regular
        case (true, false): bold
        case (false, true): italic
        case (true, true): boldItalic
        }
    }

    private static func italicVariant(of font: CTFont) -> CTFont {
        CTFontCreateCopyWithSymbolicTraits(font, 0, nil, .traitItalic, .traitItalic) ?? font
    }

    private static func measure(_ font: CTFont, scale: CGFloat, typesetting: Typesetting) -> CellMetrics {
        var glyph = CGGlyph()
        var character: UniChar = 0x4D  // "M": every glyph of a monospaced font has its advance
        CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)

        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        let natural = Int((ascent + descent + leading).rounded(.up))
        let height = max(1, Int(((ascent + descent + leading) * typesetting.lineHeight).rounded(.up)))
        let fontAdvance = Int(advance.width.rounded(.up))
        let width = max(1, Int((advance.width + typesetting.letterSpacing * scale).rounded(.up)))
        let thickness = max(1, Int(CTFontGetUnderlineThickness(font).rounded()))
        // CoreText's underline position is below the baseline and negative.
        let underline = max(1, Int((-CTFontGetUnderlinePosition(font)).rounded()))

        // The extra height splits above and below the text.
        return CellMetrics(
            width: width,
            height: height,
            baseline: Int((ascent + leading / 2).rounded(.up)) + (height - natural) / 2,
            underlineOffset: underline,
            lineThickness: thickness,
            scale: scale,
            glyphOffset: (width - fontAdvance) / 2,
            advance: fontAdvance
        )
    }
}
