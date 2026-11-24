import AppKit
import UILooks

/// The box of each pane, as the Terminals and Pane mockups draw it (components.pane; plan 28
/// phase B): rounded, with its line; the focused pane on the frame's color with the focus line
/// and a 3 pt halo outside, the others a shade darker. Layers under the panes, so the terminal
/// draws on top as before. Reads the tokens at each layout, so a theme change reaches it.
@MainActor
final class PaneChrome {
    typealias P = DesignTokens.Pane
    private var boxes: [Int: (box: CALayer, halo: CALayer)] = [:]
    private weak var host: CALayer?

    init(host: CALayer?) {
        self.host = host
    }

    /// One box per frame; the focused one lit (every pane looks focused when there is one).
    func place(_ frames: [Int: CGRect], focused: Int?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for (id, layers) in boxes where frames[id] == nil {
            layers.box.removeFromSuperlayer()
            layers.halo.removeFromSuperlayer()
            boxes[id] = nil
        }
        let radius = UILooks.pt(P.radius)
        let halo = P.Focused.shadow.first
        for (id, frame) in frames {
            let layers = boxes[id] ?? make()
            boxes[id] = layers
            let lit = id == focused || frames.count == 1
            layers.box.frame = frame
            layers.box.cornerRadius = radius
            layers.box.borderWidth = DesignTokens.Stroke.hairline
            layers.box.backgroundColor = fill(lit: lit).cgColor
            layers.box.borderColor = (lit ? P.Focused.border : P.Idle.border).cgColor
            if let glow = Glass.glow {
                place(glow: glow, layers, frame: frame, radius: radius, lit: lit)
                continue
            }
            layers.halo.shadowOpacity = 0
            // The mockup's `box-shadow: 0 0 0 3px`: a ring just outside the box.
            let spread = UILooks.pt(halo?.spread ?? 0)
            layers.halo.isHidden = !lit || halo == nil
            layers.halo.frame = frame.insetBy(dx: -spread, dy: -spread)
            layers.halo.cornerRadius = radius + spread
            layers.halo.borderWidth = spread
            layers.halo.borderColor = halo?.color.cgColor
        }
    }

    /// The box's ground: the tokens', or under the strong glass a darker glass of its own, so each
    /// pane reads as a box over the blurred wallpaper (the fork's screenshot, 2026-11-24); the
    /// grounds are see-through under any glass, and the panes vanished into the frame.
    private func fill(lit: Bool) -> NSColor {
        guard Glass.strong else { return lit ? P.Focused.bg : P.Idle.bg }
        return DesignTokens.solid(lit ? P.Focused.bg : P.Idle.bg).withAlphaComponent(lit ? 0.45 : 0.55)
    }

    /// appearance.paneBorder "glow": the border a ring in the glow's color with a soft light around
    /// it, strong on the focused pane and faint on the others; the box's own line goes.
    private func place(glow: NSColor, _ layers: (box: CALayer, halo: CALayer), frame: CGRect, radius: CGFloat, lit: Bool) {
        layers.box.borderWidth = 0
        layers.halo.isHidden = false
        layers.halo.frame = frame
        layers.halo.cornerRadius = radius
        layers.halo.borderWidth = UILooks.pt(lit ? 2 : 1)
        layers.halo.borderColor = glow.withAlphaComponent(lit ? 1 : 0.45).cgColor
        // Without a ground the shadow follows the ring alone: light inside and outside its line.
        layers.halo.shadowColor = glow.cgColor
        layers.halo.shadowOffset = .zero
        layers.halo.shadowRadius = UILooks.pt(lit ? 12 : 7)
        layers.halo.shadowOpacity = lit ? 1 : 0.45
    }

    private func make() -> (box: CALayer, halo: CALayer) {
        let halo = CALayer()
        let box = CALayer()
        host?.insertSublayer(halo, at: 0)
        host?.insertSublayer(box, above: halo)
        return (box, halo)
    }
}
