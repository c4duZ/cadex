import AppKit

/// The translucent window's glass (appearance.windowOpacity, 2026-11-18) for the pieces that live
/// in windows of their own: ⌘K, the menus, the popovers and the settings window. Under a box's
/// subviews it lays the system's frost and the box's color at the window's opacity, as the main
/// window does; with the window solid it paints the color as it was.
@MainActor
public enum Glass {
    /// The window's opacity while it is translucent; nil when solid (or in high contrast).
    public private(set) static var opacity: CGFloat?

    /// Set by the app with the window's looks; a change tells the windows that build their
    /// colors once (DesignTokens.didChange).
    public static func set(opacity new: CGFloat?) {
        guard new != opacity else { return }
        opacity = new
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
        glass.tint.layer?.backgroundColor = color.withAlphaComponent(color.alphaComponent * opacity).cgColor
        box.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

/// The frost and the tint over it, filling the box under everything else.
@MainActor
final class GlassPane: NSView {
    let tint = NSView()

    init(in box: NSView) {
        super.init(frame: box.bounds)
        autoresizingMask = [.width, .height]
        let frost = NSVisualEffectView(frame: bounds)
        frost.blendingMode = .behindWindow
        frost.material = .underWindowBackground
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

    // The box's controls under the pointer, not this.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
