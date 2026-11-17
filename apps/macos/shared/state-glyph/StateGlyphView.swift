import AppKit
import UILooks

/// The state glyph as a view (StateGlyph.swift): layers, so the working ring spins on the
/// render server without redrawing the window. It spins only while it can be seen (in a
/// window, not hidden, the window on screen) and never with "Reduce motion": the
/// performance rule that nothing out of sight costs anything (plan 17).
@MainActor
public final class StateGlyphView: NSView {
    public var state: GlyphState? { didSet { if state != oldValue { refresh() } } }
    /// The design size (7, 9, 10 or 14 in the tokens); the view adds room for the halo.
    public let size: CGFloat
    private let halo = CAShapeLayer()
    private let dot = CAShapeLayer()
    private let ring = CAShapeLayer()
    private static let spinKey = "spin"
    /// One turn per second, the pace of the macOS spinner.
    private static let turn: CFTimeInterval = 1

    public init(size: CGFloat, state: GlyphState? = nil) {
        self.size = size
        self.state = state
        super.init(frame: .zero)
        wantsLayer = true
        for sublayer in [halo, dot, ring] { layer?.addSublayer(sublayer) }
        ring.fillColor = nil
        ring.lineCap = .butt
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The glyph plus its halo margin, scaled by the zoom.
    public override var intrinsicContentSize: NSSize {
        let side = UILooks.pt(size + 2 * StateGlyphLook.margin(size: size))
        return NSSize(width: side, height: side)
    }

    public override func layout() {
        super.layout()
        refresh()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged),
                                                   name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        updateSpin()
    }

    public override func viewDidHide() { super.viewDidHide(); updateSpin() }
    public override func viewDidUnhide() { super.viewDidUnhide(); updateSpin() }

    @objc private func visibilityChanged() { updateSpin() }

    /// Whether the ring may turn now.
    var spins: Bool {
        guard state == .working, let window, !isHiddenOrHasHiddenAncestor else { return false }
        return window.occlusionState.contains(.visible) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func refresh() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let side = UILooks.pt(size)
        let rect = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        halo.isHidden = state != .needs
        dot.isHidden = state == nil || state == .working || state == .idle
        ring.isHidden = state != .working && state != .idle
        guard let state else { updateSpin(); return }
        let color = StateGlyphLook.color(state).cgColor
        let spread = UILooks.pt(StateGlyphLook.halo(size: size))
        halo.path = CGPath(ellipseIn: rect.insetBy(dx: -spread, dy: -spread), transform: nil)
        halo.fillColor = DesignTokens.Color.haloNeeds.cgColor
        dot.path = CGPath(ellipseIn: rect, transform: nil)
        dot.fillColor = color
        let stroke = UILooks.pt(StateGlyphLook.stroke(state, size: size))
        let inner = rect.insetBy(dx: stroke / 2, dy: stroke / 2)
        ring.frame = bounds
        ring.path = state == .idle ? CGPath(ellipseIn: inner, transform: nil)
            : StateGlyphLook.ringPath(in: inner)
        ring.strokeColor = color
        ring.lineWidth = stroke
        updateSpin()
    }

    private func updateSpin() {
        let spinning = ring.animation(forKey: Self.spinKey) != nil
        if spins && !spinning {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -2 * CGFloat.pi
            spin.duration = Self.turn
            spin.repeatCount = .infinity
            ring.add(spin, forKey: Self.spinKey)
        } else if !spins && spinning {
            ring.removeAnimation(forKey: Self.spinKey)
        }
    }
}
