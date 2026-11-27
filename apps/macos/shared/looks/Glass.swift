import AppKit

/// The translucent window's glass (appearance.windowOpacity, 2026-11-18) for the pieces that live
/// in windows of their own: ⌘K, the menus, the popovers and the settings window. Under a box's
/// subviews it lays the system's frost and the box's color at the window's opacity, as the main
/// window does; with the window solid it paints the color as it was.
@MainActor
public enum Glass {
    /// The window's opacity while it is translucent; nil when solid (or in high contrast).
    public private(set) static var opacity: CGFloat?
    /// The strong glass (the owner, 2026-11-24, after a fork's screenshot), on whenever the window is
    /// translucent since 2026-11-27 (one glass, the opacity its tint): the wallpaper blurred behind
    /// everything with its shapes, the panes glass boxes of their own, and ⌘K, the menus and the
    /// cards in the same glass. The system's frost alone, the old "normal", read a flat muddy gray.
    public private(set) static var strong = false
    /// appearance.paneBorder "glow": the panes' border in this color with a soft glow (the work
    /// color, else the accent); nil keeps the line.
    public private(set) static var glow: NSColor?

    /// The system's frost for the glass: the strong one darker and cleaner, so the color under it
    /// is the desktop's and the tint's, not the material's own gray.
    public static var material: NSVisualEffectView.Material { strong ? .hudWindow : .underWindowBackground }
    /// The frost's own look: dark under the strong glass whatever the window's, so it never goes
    /// to the light gray the HUD material takes over bright windows (seen in a capture, 2026-11-24).
    public static var frostAppearance: NSAppearance? { strong ? NSAppearance(named: .vibrantDark) : nil }
    /// The tint's alpha over the blur, from the window's opacity: the slider's floor (10%) is the
    /// strong glass as it was (`floorTint`, a dark glass the wallpaper shows through; the fork's
    /// screenshot), and the rest of the slider runs from there to a solid window (the owner,
    /// 2026-11-27: "os 10% do vidro forte sejam os 10% aqui"). The strong glass held 0.62 at every
    /// position before, so the slider changed nothing.
    public static var tint: CGFloat? { opacity.map(tint(for:)) }
    static let floorTint: CGFloat = 0.62

    /// The tint for an opacity: 0.1 → `floorTint`, 1 → 1, in a line between.
    static func tint(for opacity: CGFloat) -> CGFloat {
        let along = min(max((opacity - 0.1) / 0.9, 0), 1)
        return floorTint + (1 - floorTint) * along
    }
    /// The tint of what floats over the window (⌘K, ⌘P, the menus, the popovers, the cards,
    /// settings): ten points above the window's, so it reads over the frame it covers (the owner,
    /// 2026-11-24).
    public static var panelTint: CGFloat? { tint.map { min($0 + 0.1, 1) } }

    /// The strong glass's window server blur, only in a window with a title bar: the window server
    /// blurs the window's whole rectangle, and it cuts the corners of a titled window only. A
    /// borderless panel with rounded corners (⌘K, the menus, the popovers, the cards) showed a blurred
    /// square around them (the owner's screenshot, 2026-11-27): they keep the frost, cut to their shape.
    public static func blursWindow(_ window: NSWindow?) -> Bool {
        strong && window?.styleMask.contains(.titled) == true
    }

    /// A mask for a frost in a box with rounded corners: stretched, the corners stay round.
    public static func roundedMask(_ radius: CGFloat) -> NSImage? {
        guard radius > 0 else { return nil }
        let side = radius * 2 + 1
        let mask = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        return mask
    }

    /// Set by the app with the window's looks; a change tells the windows that build their
    /// colors once (DesignTokens.didChange).
    public static func set(opacity new: CGFloat?, strong newStrong: Bool = false, glow newGlow: NSColor? = nil) {
        guard new != opacity || newStrong != strong || newGlow != glow else { return }
        opacity = new
        strong = newStrong && new != nil
        glow = newGlow
        NotificationCenter.default.post(name: DesignTokens.didChange, object: nil)
    }

    /// Paints `box` in `color`: solid, or frost with the color at the glass's opacity. The box
    /// must draw nothing of its own but its layer (its subviews go over the frost), and clip to
    /// its corners for the frost to follow them.
    public static func dress(_ box: NSView, _ color: NSColor) {
        box.wantsLayer = true
        let pane = box.subviews.first { $0 is GlassPane } as? GlassPane
        guard let opacity else {
            pane?.isHidden = true
            box.layer?.backgroundColor = color.cgColor
            return
        }
        let glass = pane ?? GlassPane(in: box)
        glass.isHidden = false
        glass.frost.material = material
        glass.frost.appearance = frostAppearance
        // The strong glass: the window server's blur of the desktop, as the main window's, in a titled
        // window; elsewhere the frost, cut to the box's corners (blursWindow).
        glass.frost.maskImage = roundedMask(box.layer?.cornerRadius ?? 0)
        glass.blurWindow()
        glass.tint.layer?.backgroundColor = color.withAlphaComponent(color.alphaComponent * (panelTint ?? opacity)).cgColor
        box.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

/// The frost and the tint over it, filling the box under everything else.
@MainActor
final class GlassPane: NSView {
    let tint = NSView()
    let frost = NSVisualEffectView()

    init(in box: NSView) {
        super.init(frame: box.bounds)
        autoresizingMask = [.width, .height]
        frost.frame = bounds
        frost.blendingMode = .behindWindow
        frost.material = Glass.material
        frost.state = .active
        frost.autoresizingMask = [.width, .height]
        tint.frame = bounds
        tint.wantsLayer = true
        tint.autoresizingMask = [.width, .height]
        addSubview(frost)
        addSubview(tint)
        box.addSubview(self, positioned: .below, relativeTo: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("GlassPane is created in code") }

    /// The box's window blurred behind under the strong glass (WindowBlur), none otherwise. A window
    /// made deferred (settings, the menus, the cards) has no number until it shows, and the blur set
    /// before was dropped: the settings window showed the terminal behind it sharp (the owner's
    /// screenshot, 2026-11-27). Shown, it has one at once, so the next turns of the loop try again,
    /// for a second at most (the occlusion notice did not come for a window's first showing).
    func blurWindow(tries: Int = 20) {
        guard let window else { return }
        frost.isHidden = Glass.blursWindow(window)
        guard window.windowNumber <= 0 else { return WindowBlur.set(window, radius: Glass.blursWindow(window) && !isHidden ? WindowBlur.strong : 0) }
        guard tries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.blurWindow(tries: tries - 1) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        blurWindow()
    }

    // The box's controls under the pointer, not this.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
