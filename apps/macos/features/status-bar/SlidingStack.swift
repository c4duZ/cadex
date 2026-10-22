import AppKit

/// A side of the status bar whose items slide to their new places when one
/// of them changes width (the folder, the branch, the account), instead of
/// jumping (the owner, 2026-10-22: "things change place"). Each layout pass
/// notes where the items were, lets them take their new frames, then
/// animates each moved one from the old place with a transform, which moves
/// the drawing and never the layout.
@MainActor
final class SlidingStack: NSStackView {
    static let duration: CFTimeInterval = 0.22

    override func layout() {
        let before = Dictionary(uniqueKeysWithValues: arrangedSubviews.map { (ObjectIdentifier($0), $0.frame.minX) })
        super.layout()
        guard window != nil else { return }
        for view in arrangedSubviews where !view.isHidden {
            guard let old = before[ObjectIdentifier(view)], abs(old - view.frame.minX) > 0.5 else { continue }
            Self.slide(view, by: old - view.frame.minX)
        }
    }

    /// From `offset` points away back to its place, easing out.
    static func slide(_ view: NSView, by offset: CGFloat) {
        view.wantsLayer = true
        let slide = CABasicAnimation(keyPath: "transform.translation.x")
        slide.fromValue = offset
        slide.toValue = 0
        slide.duration = duration
        slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
        view.layer?.add(slide, forKey: "slide")
    }

    /// A text that changes fades into the new one instead of switching.
    static func fade(_ view: NSView) {
        guard view.window != nil else { return }
        view.wantsLayer = true
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.18
        view.layer?.add(fade, forKey: "fade")
    }
}
