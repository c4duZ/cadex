import AppKit

/// How a color of the new frame follows the theme (tools/design/theme_recipes.py): the frame took
/// its colors straight from the mockups, and every theme looked like Cadex Night (owner,
/// 2026-11-17). With Cadex Night the mockups' values are used as they are.
public enum ThemeRecipe: Sendable {
    /// mix(chrome, text, f): backgrounds, lines and grays.
    case neutral(CGFloat)
    /// mix(chrome, hue, f): a background tinted toward a state color.
    case tint(UInt32, CGFloat)
    /// mix(hue, text, g): a colored text, lighter on dark themes and darker on light ones.
    case ink(UInt32, CGFloat)
}

public extension DesignTokens {
    /// The theme's colors by token name; empty with Cadex Night. Written on the main thread only,
    /// when the theme changes (`applyTheme`); read wherever a token is.
    nonisolated(unsafe) internal static var palette: [String: NSColor] = [:]
    /// The grounds' solid colors while the palette has them as glass: a text or icon painted in a
    /// ground's color (the primary button's) keeps it solid through `repaint`.
    nonisolated(unsafe) internal static var solidGrounds: [String: NSColor] = [:]

    /// A themed token: the theme's color when one is set, else Cadex Night's.
    static func themed(_ name: String, _ cadexNight: @autoclosure () -> NSColor) -> NSColor {
        palette[name] ?? cadexNight()
    }

    /// The grounds of the frame: what a translucent window (appearance.windowOpacity) turns into
    /// glass. Cards, buttons, chips and selections over them stay solid.
    static let grounds = ["bg.window", "bg.inset", "bg.drawer", "bg.paneIdle", "bg.chrome", "bg.sidebar"]

    /// The frame in a theme's colors, from its frame color and its text (`nil`: Cadex Night,
    /// the mockups as they are). With `glass` the grounds go see-through: the window paints
    /// one tint under them (WorkspaceView), so the frame, the sidebar and the panes are one glass
    /// instead of translucent layers stacking into a solid one. Returns whether anything changed.
    @MainActor @discardableResult
    static func applyTheme(chrome: NSColor?, text: NSColor?, glass: Bool = false) -> Bool {
        var next: [String: NSColor] = [:]
        if let chrome = chrome?.usingColorSpace(.sRGB), let text = text?.usingColorSpace(.sRGB) {
            for (name, recipe) in recipes {
                next[name] = switch recipe {
                case .neutral(let f): mix(chrome, text, f)
                case .tint(let hue, let f): mix(chrome, rgb(hue), f)
                case .ink(let hue, let g): mix(rgb(hue), text, g)
                }
            }
        }
        var solid: [String: NSColor] = [:]
        if glass {
            // Not quite clear, and each its own alpha (1/255, 2/255…): `repaint` finds a layer's
            // token by its color, so two grounds both clear would come back as the same one,
            // and a view that was clear on its own would be taken for a ground.
            for (i, name) in grounds.enumerated() {
                let color = next[name] ?? cadexNight[name].map { rgb($0) } ?? .clear
                solid[name] = color
                next[name] = color.withAlphaComponent(CGFloat(i + 1) / 255)
            }
        }
        guard !samePalette(next, palette) else { return false }
        palette = next
        solidGrounds = solid
        NotificationCenter.default.post(name: didChange, object: nil)
        return true
    }

    private static func mix(_ a: NSColor, _ b: NSColor, _ f: CGFloat) -> NSColor {
        let a = a.usingColorSpace(.sRGB) ?? a, b = b.usingColorSpace(.sRGB) ?? b
        func channel(_ x: CGFloat, _ y: CGFloat) -> CGFloat { min(max(x + (y - x) * f, 0), 1) }
        return NSColor(srgbRed: channel(a.redComponent, b.redComponent), green: channel(a.greenComponent, b.greenComponent),
                       blue: channel(a.blueComponent, b.blueComponent), alpha: 1)
    }

    private static func samePalette(_ a: [String: NSColor], _ b: [String: NSColor]) -> Bool {
        a.count == b.count && a.allSatisfy { key, color in b[key].map { $0.isEqual(color) } ?? false }
    }

    /// Posted when the tokens' colors change (a theme, or the window turning translucent): windows
    /// that build their colors once (settings) build them again.
    static let didChange = Notification.Name("DesignTokens.didChange")

    /// A color as it is without glass: an opaque window (settings) lays its ground in it, and
    /// the see-through grounds of its views show that and not the black behind (2026-11-18).
    static func solid(_ color: NSColor) -> NSColor {
        color.alphaComponent < 1 ? color.withAlphaComponent(1) : color
    }

    /// Every themed token's color now, by name: what `repaint` maps from. A ground under glass
    /// also gives its solid color, as "<name>#solid".
    static func themedColors() -> [String: NSColor] {
        var colors = Dictionary(uniqueKeysWithValues: cadexNight.map { name, value in (name, palette[name] ?? rgb(value)) })
        for name in grounds { colors[name + "#solid"] = solidGrounds[name] ?? colors[name] }
        return colors
    }

    /// The frame painted again after a theme change: every layer, text, icon and button color
    /// that was a themed token's (`before`, from `themedColors()` taken before `applyTheme`)
    /// becomes that token's color now, and every view draws again. Views that read the tokens
    /// as they draw need only the redraw; the ones that set a color when built get it here, so
    /// no view has to rebuild for a theme (2026-11-17).
    @MainActor
    static func repaint(_ root: NSView, from before: [String: NSColor]) {
        var map: [ColorKey: NSColor] = [:], ink: [ColorKey: NSColor] = [:]
        let now = themedColors()
        for (name, old) in before where !name.hasSuffix("#solid") {
            guard let new = now[name] else { continue }
            map[ColorKey(old)] = new
            ink[ColorKey(old)] = new
        }
        // Text and icons in a ground's color stay solid under glass (the primary button's label).
        for name in grounds {
            if let old = before[name + "#solid"], let new = now[name + "#solid"] { ink[ColorKey(old)] = new }
        }
        guard !map.isEmpty else { return }
        Repaint(map: map, ink: ink).view(root)
    }
}

/// A color as 8-bit sRGB channels and alpha: equal tokens compare equal however they were made.
struct ColorKey: Hashable {
    let r: Int, g: Int, b: Int, a: Int

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color
        r = Int((c.redComponent * 255).rounded()); g = Int((c.greenComponent * 255).rounded())
        b = Int((c.blueComponent * 255).rounded()); a = Int((c.alphaComponent * 255).rounded())
    }

    init?(_ color: CGColor) {
        guard let ns = NSColor(cgColor: color), ns.usingColorSpace(.sRGB) != nil else { return nil }
        self.init(ns)
    }
}

@MainActor
private struct Repaint {
    /// For backgrounds, borders and shapes.
    let map: [ColorKey: NSColor]
    /// For text and icons: the same, but a ground stays solid under glass.
    let ink: [ColorKey: NSColor]

    func swap(_ color: NSColor?) -> NSColor? {
        guard let color else { return nil }
        return ink[ColorKey(color)]
    }

    func swap(_ color: CGColor?) -> CGColor? {
        guard let color, let key = ColorKey(color) else { return nil }
        return map[key]?.cgColor
    }

    func view(_ view: NSView) {
        if let layer = view.layer { self.layer(layer) }
        switch view {
        case let field as NSTextField:
            // The runs read before the plain color changes: setting textColor recolors them, and
            // read after they were swapped twice (Cadex Night's text #E7E8EA became Cadex Day's
            // #1D1F23, which is Night's bg.chip, and then Day's light chip: the chosen segment's
            // label vanished, 2026-11-18). The plain color first, then any runs of their own.
            let attributed = text(field.attributedStringValue)
            if let new = swap(field.textColor) { field.textColor = new }
            if let attributed { field.attributedStringValue = attributed }
        case let button as NSButton:
            if let new = swap(button.contentTintColor) { button.contentTintColor = new }
            if let attributed = text(button.attributedTitle) { button.attributedTitle = attributed }
        case let image as NSImageView:
            if let new = swap(image.contentTintColor) { image.contentTintColor = new }
        default:
            break
        }
        view.needsDisplay = true
        for sub in view.subviews { self.view(sub) }
    }

    func layer(_ layer: CALayer) {
        if let new = swap(layer.backgroundColor) { layer.backgroundColor = new }
        if let new = swap(layer.borderColor) { layer.borderColor = new }
        if let new = swap(layer.shadowColor) { layer.shadowColor = new }
        if let shape = layer as? CAShapeLayer {
            if let new = swap(shape.fillColor) { shape.fillColor = new }
            if let new = swap(shape.strokeColor) { shape.strokeColor = new }
        }
        for sub in layer.sublayers ?? [] { self.layer(sub) }
    }

    /// The string with its themed colors swapped, or nil when none was.
    func text(_ string: NSAttributedString) -> NSAttributedString? {
        guard string.length > 0 else { return nil }
        let copy = NSMutableAttributedString(attributedString: string)
        var changed = false
        for key in [NSAttributedString.Key.foregroundColor, .backgroundColor] {
            string.enumerateAttribute(key, in: NSRange(location: 0, length: string.length)) { value, range, _ in
                if let new = swap(value as? NSColor) { copy.addAttribute(key, value: new, range: range); changed = true }
            }
        }
        return changed ? copy : nil
    }
}
