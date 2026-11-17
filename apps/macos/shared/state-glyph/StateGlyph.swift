import AppKit
import UILooks

/// The app's one sign of state (docs/adr/0035-work-frame.md; components.stateGlyph of
/// docs/design/work-frame/tokens.json): the same in the tree, the tabs, the bell, ⌘J and the
/// board, so color means state and nothing else.
public enum GlyphState: String, CaseIterable, Sendable {
    /// In a turn: a blue ring open at the top, the only thing that moves (it spins).
    case working
    /// A permission or a question: amber with a halo.
    case needs
    /// The turn ended or the task reported done: green.
    case done
    /// Exited, capped or failed to start: red.
    case failed
    /// Nothing running (hibernated, or no agent): a gray outline.
    case idle
    /// Done and waiting for the owner's review: purple.
    case review
}

/// How each state looks, from the tokens: the views and the hand-drawn tab strip share it.
@MainActor
public enum StateGlyphLook {
    typealias Glyph = DesignTokens.StateGlyph

    /// The glyph's own color.
    public static func color(_ state: GlyphState) -> NSColor {
        switch state {
        case .working: Glyph.Working.ring
        case .needs: Glyph.Needs.fill
        case .done: Glyph.Done.fill
        case .failed: Glyph.Failed.fill
        case .idle: Glyph.Idle.ring
        case .review: Glyph.Review.fill
        }
    }

    /// The ring's width at a design size: the thinner stroke for the smallest glyph, the
    /// mockups' 2 pt rings at 9 and 10, 2.5 at the 14 of the anatomy.
    public static func stroke(_ state: GlyphState, size: CGFloat) -> CGFloat {
        if state == .idle { return Glyph.Idle.stroke }
        if size <= Glyph.sizes[0] { return Glyph.Working.strokeSmall }
        return size >= Glyph.sizes[3] ? DesignTokens.Stroke.glyphLarge : Glyph.Working.stroke
    }

    /// The halo around "needs you": 3 pt, 4 at the largest size (shadow tokens).
    public static func halo(size: CGFloat) -> CGFloat {
        let layers = size >= Glyph.sizes[3] ? DesignTokens.Shadow.haloNeedsLarge : DesignTokens.Shadow.haloNeeds
        return layers.first?.spread ?? 0
    }

    /// Room around the glyph so the halo is not cut: views are this much larger on each side.
    public static func margin(size: CGFloat) -> CGFloat { halo(size: size) }

    /// A ring open at the top: from the top-right to the top-left, the long way round, in a
    /// y-up space. The gap is the quarter the mockups leave transparent (border-top).
    static func ringPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let radius = min(rect.width, rect.height) / 2
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                    startAngle: .pi / 4, endAngle: 3 * .pi / 4, clockwise: true)
        return path
    }

    /// Draws one still frame (the tab strip and snapshots): `angle` turns the working ring.
    public static func draw(_ state: GlyphState, in rect: NSRect, angle: CGFloat = 0) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let size = min(rect.width, rect.height)
        let stroke = stroke(state, size: size)
        context.saveGState()
        defer { context.restoreGState() }
        switch state {
        case .working, .idle:
            let inner = rect.insetBy(dx: stroke / 2, dy: stroke / 2)
            context.setStrokeColor(color(state).cgColor)
            context.setLineWidth(stroke)
            if state == .idle {
                context.strokeEllipse(in: inner)
            } else {
                context.translateBy(x: rect.midX, y: rect.midY)
                context.rotate(by: -angle)
                context.translateBy(x: -rect.midX, y: -rect.midY)
                context.addPath(ringPath(in: inner))
                context.strokePath()
            }
        case .needs:
            let halo = halo(size: size)
            context.setFillColor(DesignTokens.Color.haloNeeds.cgColor)
            context.fillEllipse(in: rect.insetBy(dx: -halo, dy: -halo))
            context.setFillColor(color(state).cgColor)
            context.fillEllipse(in: rect)
        case .done, .failed, .review:
            context.setFillColor(color(state).cgColor)
            context.fillEllipse(in: rect)
        }
    }
}
