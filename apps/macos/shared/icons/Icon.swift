import AppKit
import CoreText

/// The app's icons: Phosphor (MIT), regular weight, drawn from its icon
/// font (docs/adr/0008-phosphor-icons.md). Each case is a glyph; its value
/// is the codepoint from the style.css of @phosphor-icons/web 2.1.2, the
/// same release as Resources/Phosphor-Regular.ttf. Add icons here by name.
public enum Icon: UInt32, CaseIterable, Sendable {
    case appWindow = 0xE5DA
    case arrowCircleUp = 0xE030
    case arrowClockwise = 0xE036
    case arrowCounterClockwise = 0xE038
    case arrowDown = 0xE03E
    case arrowLeft = 0xE058
    case arrowRight = 0xE06C
    case arrowsClockwise = 0xE094
    case arrowsInLineVertical = 0xE532
    case arrowSquareOut = 0xE5DE
    case arrowUp = 0xE08E
    case arrowUUpLeft = 0xE08A
    case bell = 0xE0CE
    case bracketsCurly = 0xE860
    case caretDown = 0xE136
    case caretRight = 0xE13A
    case caretUp = 0xE13C
    case check = 0xE182
    case checkCircle = 0xE184
    case clipboardText = 0xE198
    case clockCounterClockwise = 0xE1A0
    case code = 0xE1BC
    case coffee = 0xE1C2
    case command = 0xE1C4
    case copy = 0xE1CA
    case cpu = 0xE610
    case crosshair = 0xE1D6
    case dotsSixVertical = 0xEAE2
    case dotsThree = 0xE1FE
    case eye = 0xE220
    case file = 0xE230
    case fileArchive = 0xEB2A
    case fileAudio = 0xEA20
    case fileCode = 0xE914
    case fileImage = 0xEA24
    case fileMd = 0xED50
    case filePdf = 0xE702
    case filePlus = 0xE236
    case files = 0xE710
    case fileText = 0xE23A
    case fileVideo = 0xEA22
    case fireSimple = 0xE620
    case folder = 0xE24A
    case folderOpen = 0xE256
    case folderPlus = 0xE258
    case gearSix = 0xE272
    case gitBranch = 0xE278
    case gitCommit = 0xE27A
    case gitDiff = 0xE27C
    case globe = 0xE288
    case info = 0xE2CE
    case keyboard = 0xE2D8
    case link = 0xE2E2
    case lockKey = 0xE2FE
    case magnifyingGlass = 0xE30C
    case memory = 0xE9C4
    case minus = 0xE32A
    case palette = 0xE6C8
    case path = 0xE39C
    case pencilSimple = 0xE3B4
    case plus = 0xE3D4
    case question = 0xE3E8
    case sidebar = 0xEAB6
    case slidersHorizontal = 0xE434
    case sparkle = 0xE6A2
    case squareSplitHorizontal = 0xE870
    case squareSplitVertical = 0xE874
    case stack = 0xE466
    case terminalWindow = 0xEAE8
    case trash = 0xE4A6
    case x = 0xE4F6

    /// The fonts' family names inside the TTFs.
    static let fontName = "Phosphor"
    static let fillFontName = "Phosphor-Fill"

    /// The icon as a template image: buttons tint it with their color.
    /// `filled` draws the fill weight: an icon that shows on (filled) or
    /// off (the outline), as keep-awake's (docs/adr/0008-phosphor-icons.md).
    @MainActor
    public func image(size: CGFloat = 16, filled: Bool = false) -> NSImage {
        let font = filled ? Self.fillFont(size: size) : Self.font(size: size)
        let glyph = String(UnicodeScalar(rawValue)!)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let text = NSAttributedString(string: glyph, attributes: attributes)
            let bounds = text.size()
            text.draw(at: NSPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The icon font at `size`, registered on first use.
    @MainActor
    public static func font(size: CGFloat) -> NSFont {
        registerFont()
        return NSFont(name: fontName, size: size) ?? .systemFont(ofSize: size)
    }

    /// The fill weight at `size` (same codepoints as the regular one).
    @MainActor
    public static func fillFont(size: CGFloat) -> NSFont {
        registerFont()
        return NSFont(name: fillFontName, size: size) ?? font(size: size)
    }

    @MainActor private static var registered = false

    @MainActor
    private static func registerFont() {
        guard !registered else { return }
        registered = true
        // In Cadex.app the font is in Contents/Resources (packaging/build.sh):
        // SwiftPM's Bundle.module looks in the app's root folder, which the
        // signature does not allow, then at a path on the build machine.
        for name in ["Phosphor-Regular", "Phosphor-Fill"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf")
                ?? Bundle.module.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
