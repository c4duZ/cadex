import CoreGraphics
import CoreText
import Metal

/// Where one rasterized glyph sits in the atlas texture.
struct AtlasGlyph {
    /// Pixel rectangle in the atlas.
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    /// Emoji and other color glyphs are drawn as-is; the rest are a coverage
    /// mask tinted with the cell's foreground color.
    var isColor: Bool
}

/// Rasterizes each (text, style, width) once with CoreText and keeps it in
/// one GPU texture. Glyphs are drawn at whole-pixel positions into a bitmap
/// exactly the cell size (plus padding for overhangs), so sampling is 1:1.
final class GlyphAtlas {
    private struct Key: Hashable {
        var text: String
        var bold: Bool
        var italic: Bool
        var cells: Int
    }

    static let size = 2048
    let texture: MTLTexture
    let font: TerminalFont
    /// Room around the cell for italic and bold overhangs.
    let padX: Int
    let padY: Int

    private var glyphs: [Key: AtlasGlyph] = [:]
    private var shelfX = 0
    private var shelfY = 0
    private var shelfHeight = 0

    init?(device: MTLDevice, font: TerminalFont) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: Self.size, height: Self.size, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        self.texture = texture
        self.font = font
        padX = max(2, font.metrics.width / 2)
        padY = max(2, font.metrics.height / 4)
    }

    func glyph(text: String, bold: Bool, italic: Bool, cells: Int) -> AtlasGlyph? {
        let key = Key(text: text, bold: bold, italic: italic, cells: cells)
        if let hit = glyphs[key] { return hit }
        guard let glyph = rasterize(key) else { return nil }
        glyphs[key] = glyph
        return glyph
    }

    private func rasterize(_ key: Key) -> AtlasGlyph? {
        let m = font.metrics
        let width = m.width * key.cells + padX * 2
        let height = m.height + padY * 2
        guard let slot = allocate(width: width, height: height) else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            // White text: monochrome glyphs become a coverage mask in alpha;
            // color fonts (emoji) ignore the fill and keep their colors.
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font.font(bold: key.bold, italic: key.italic),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: key.text, attributes: attributes))
            // CoreGraphics' origin is bottom-left: baseline measured from the bottom.
            context.textPosition = CGPoint(x: padX, y: height - padY - m.baseline)
            CTLineDraw(line, context)
            return true
        }
        guard drawn else { return nil }

        texture.replace(
            region: MTLRegionMake2D(slot.x, slot.y, width, height), mipmapLevel: 0,
            withBytes: pixels, bytesPerRow: width * 4)
        return AtlasGlyph(x: slot.x, y: slot.y, width: width, height: height, isColor: Self.hasColor(pixels))
    }

    /// Shelf packing: fill rows left to right. When the texture is full,
    /// start over; glyphs still needed are rasterized again on demand.
    private func allocate(width: Int, height: Int) -> (x: Int, y: Int)? {
        if width > Self.size || height > Self.size { return nil }
        if shelfX + width > Self.size {
            shelfY += shelfHeight
            shelfX = 0
            shelfHeight = 0
        }
        if shelfY + height > Self.size {
            glyphs.removeAll()
            shelfX = 0
            shelfY = 0
            shelfHeight = 0
        }
        let slot = (x: shelfX, y: shelfY)
        shelfX += width
        shelfHeight = max(shelfHeight, height)
        return slot
    }

    /// A glyph drawn in white has r == g == b everywhere; anything else came
    /// from a color font.
    private static func hasColor(_ rgba: [UInt8]) -> Bool {
        var i = 0
        while i < rgba.count {
            if rgba[i] != rgba[i + 1] || rgba[i + 1] != rgba[i + 2] { return true }
            i += 4
        }
        return false
    }
}
