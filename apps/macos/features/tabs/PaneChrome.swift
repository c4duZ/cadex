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
            layers.box.backgroundColor = (lit ? P.Focused.bg : P.Idle.bg).cgColor
            layers.box.borderColor = (lit ? P.Focused.border : P.Idle.border).cgColor
            // The mockup's `box-shadow: 0 0 0 3px`: a ring just outside the box.
            let spread = UILooks.pt(halo?.spread ?? 0)
            layers.halo.isHidden = !lit || halo == nil
            layers.halo.frame = frame.insetBy(dx: -spread, dy: -spread)
            layers.halo.cornerRadius = radius + spread
            layers.halo.borderWidth = spread
            layers.halo.borderColor = halo?.color.cgColor
        }
    }

    private func make() -> (box: CALayer, halo: CALayer) {
        let halo = CALayer()
        let box = CALayer()
        host?.insertSublayer(halo, at: 0)
        host?.insertSublayer(box, above: halo)
        return (box, halo)
    }
}
