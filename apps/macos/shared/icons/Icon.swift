import AppKit
import CoreText

/// The app's icons: Phosphor (MIT), regular weight, drawn from its icon
/// font (docs/adr/0008-phosphor-icons.md). Each case is a glyph; its value
/// is the codepoint from the style.css of @phosphor-icons/web 2.1.2, the
/// same release as Resources/Phosphor-Regular.ttf. Add icons here by name.
public enum Icon: UInt32, CaseIterable, Sendable {
    case arrowCounterClockwise = 0xE038
    case bell = 0xE0CE
    case caretDown = 0xE136
    case caretRight = 0xE13A
    case caretUp = 0xE13C
    case check = 0xE182
    case command = 0xE1C4
    case folder = 0xE24A
    case gearSix = 0xE272
    case gitBranch = 0xE278
    case info = 0xE2CE
    case keyboard = 0xE2D8
    case magnifyingGlass = 0xE30C
    case palette = 0xE6C8
    case plus = 0xE3D4
    case sidebar = 0xEAB6
    case terminalWindow = 0xEAE8
    case x = 0xE4F6

    /// The font's family name inside the TTF.
    static let fontName = "Phosphor"

    /// The icon as a template image: buttons tint it with their color.
    @MainActor
    public func image(size: CGFloat = 16) -> NSImage {
        let font = Self.font(size: size)
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

    @MainActor private static var registered = false

    @MainActor
    private static func registerFont() {
        guard !registered else { return }
        registered = true
        guard let url = Bundle.module.url(forResource: "Phosphor-Regular", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}
