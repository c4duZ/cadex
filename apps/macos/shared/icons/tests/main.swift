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
    ("icons are template images of the asked size", {
        let image = Icon.plus.image(size: 20)
        expect(image.isTemplate && image.size == NSSize(width: 20, height: 20))
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
])
exit(exitCode)
