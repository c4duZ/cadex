import AppKit
import Checks
import CoreText
@testable import Icons

// Tests of the shared icons. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
    ("the Phosphor font loads and has a glyph for every icon", {
        let font = Icon.font(size: 16)
        expect(font.familyName == "Phosphor", "\(String(describing: font.familyName))")
        for icon in Icon.allCases {
            var unichars = Array(String(UnicodeScalar(icon.rawValue)!).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: unichars.count)
            let found = CTFontGetGlyphsForCharacters(font as CTFont, &unichars, &glyphs, unichars.count)
            expect(found && glyphs[0] != 0, "\(icon) has no glyph")
        }
    }),
    ("the fill weight loads, with the same codepoints (keep-awake's coffee)", {
        let font = Icon.fillFont(size: 16)
        expect(font.fontName == Icon.fillFontName, font.fontName)
        var unichars = Array(String(UnicodeScalar(Icon.coffee.rawValue)!).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: unichars.count)
        expect(CTFontGetGlyphsForCharacters(font as CTFont, &unichars, &glyphs, unichars.count) && glyphs[0] != 0)
    }),
    ("icons are template images of the asked size", {
        let image = Icon.plus.image(size: 20)
        expect(image.isTemplate && image.size == NSSize(width: 20, height: 20))
    }),
    ("a fitted icon is drawn in the middle, its longer side the same for all", {
        // The inked box of each icon at 64 pt, from its pixels.
        @MainActor func inked(_ icon: Icon) -> NSRect {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            icon.fittedImage(size: 64).draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
            NSGraphicsContext.restoreGraphicsState()
            var box = NSRect.null
            for x in 0..<64 { for y in 0..<64 where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { box = box.union(NSRect(x: x, y: y, width: 1, height: 1)) } }
            return box
        }
        for icon in [Icon.files, .gitBranch, .sparkle, .gauge] {
            let box = inked(icon)
            expect(abs(box.midX - 32) <= 1 && abs(box.midY - 32) <= 1, "\(icon) off the middle: \(box)")
            expect(abs(max(box.width, box.height) - 52) <= 2, "\(icon) longer side: \(box)")
        }
    }),
    ("file and folder icons from the Material pack, Phosphor for the rest", {
        expect(FileIcons.image(forFileNamed: "Dockerfile") != nil)
        expect(FileIcons.image(forFileNamed: "main.py") != nil)
        expect(FileIcons.image(forFileNamed: "types.d.ts") != nil)
        expect(FileIcons.image(forFileNamed: ".env") != nil)
        expect(FileIcons.image(forFileNamed: "notas.qualquer") == nil)
        expect(FileIcons.folderImage(named: "src") != nil)
        expect(FileIcons.folderImage(named: ".github") != nil)
        expect(FileIcons.folderImage(named: "minha-pasta") == nil)
    }),
    ("each provider logo draws something, and a picture of them with CADEX_SNAPSHOT_DIR", {
        let side: CGFloat = 48
        let strip = NSImage(size: NSSize(width: side * CGFloat(ProviderLogo.allCases.count), height: side), flipped: false) { _ in
            NSColor(white: 0.1, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: side * CGFloat(ProviderLogo.allCases.count), height: side).fill()
            for (index, logo) in ProviderLogo.allCases.enumerated() {
                let image = logo.image(size: side - 12)
                let tinted = NSImage(size: image.size, flipped: false) { r in
                    image.draw(in: r)
                    NSColor.white.set()
                    r.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: NSRect(x: CGFloat(index) * side + 6, y: 6, width: side - 12, height: side - 12))
            }
            return true
        }
        for logo in ProviderLogo.allCases {
            let bitmap = NSBitmapImageRep(data: logo.image(size: 32).tiffRepresentation ?? Data())
            var ink = 0
            if let bitmap { for x in 0..<bitmap.pixelsWide { for y in 0..<bitmap.pixelsHigh where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { ink += 1 } } }
            expect(ink > 20, "\(logo) draws nothing")
        }
        if let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"], let tiff = strip.tiffRepresentation {
            try? NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/provider-logos.png"))
        }
    }),
])
exit(exitCode)
