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
}

/// The terminal font (SF Mono 13 pt by default) in its four styles, sized
/// in device pixels for one display scale.
final class TerminalFont {
    static let defaultPointSize: CGFloat = 13

    let metrics: CellMetrics
    private let regular: CTFont
    private let bold: CTFont
    private let italic: CTFont
    private let boldItalic: CTFont

    init(pointSize: CGFloat = TerminalFont.defaultPointSize, scale: CGFloat) {
        let pixelSize = pointSize * scale
        // monospacedSystemFont is SF Mono, which ships with macOS.
        regular = NSFont.monospacedSystemFont(ofSize: pixelSize, weight: .regular) as CTFont
        bold = NSFont.monospacedSystemFont(ofSize: pixelSize, weight: .bold) as CTFont
        italic = Self.italicVariant(of: regular)
        boldItalic = Self.italicVariant(of: bold)
        metrics = Self.measure(regular, scale: scale)
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

    private static func measure(_ font: CTFont, scale: CGFloat) -> CellMetrics {
        var glyph = CGGlyph()
        var character: UniChar = 0x4D  // "M": every glyph of a monospaced font has its advance
        CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)

        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        let height = Int((ascent + descent + leading).rounded(.up))
        let thickness = max(1, Int(CTFontGetUnderlineThickness(font).rounded()))
        // CoreText's underline position is below the baseline and negative.
        let underline = max(1, Int((-CTFontGetUnderlinePosition(font)).rounded()))

        return CellMetrics(
            width: Int(advance.width.rounded(.up)),
            height: height,
            baseline: Int((ascent + leading / 2).rounded(.up)),
            underlineOffset: underline,
            lineThickness: thickness,
            scale: scale
        )
    }
}
