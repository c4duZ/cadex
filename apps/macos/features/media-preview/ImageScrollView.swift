import AppKit

/// The image viewer's scroll view, with the gestures of the macOS Preview
/// (owner, 2026-10-21): ⌘+scroll zooms around the pointer, dragging the
/// image moves it with an open hand. Pinch comes with allowsMagnification.
@MainActor
final class ImageScrollView: NSScrollView {
    /// The user zoomed by hand: the image stops fitting the tab.
    var onZoomByHand: (() -> Void)?
    private var dragStart: (point: NSPoint, origin: NSPoint)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        NotificationCenter.default.addObserver(forName: NSScrollView.willStartLiveMagnifyNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onZoomByHand?() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ImageScrollView is created in code") }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command), let document = documentView else { return super.scrollWheel(with: event) }
        onZoomByHand?()
        let factor = Self.zoomFactor(deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas)
        let target = min(max(magnification * factor, minMagnification), maxMagnification)
        setMagnification(target, centeredAt: document.convert(event.locationInWindow, from: nil))
    }

    /// Up zooms in. A trackpad's fine deltas zoom by 1 % a point; a wheel's
    /// lines by 10 % each.
    static func zoomFactor(deltaY: CGFloat, precise: Bool) -> CGFloat {
        precise ? max(0.5, min(2, 1 + deltaY * 0.01)) : pow(1.1, deltaY)
    }

    // MARK: Dragging the image

    /// Presses on the image come here, not to the image view.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === documentView ? self : hit
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(contentView.frame, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = (event.locationInWindow, contentView.bounds.origin)
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let origin = Self.dragOrigin(start: dragStart.origin, from: dragStart.point, to: event.locationInWindow,
                                     magnification: magnification)
        var bounds = contentView.bounds
        bounds.origin = origin
        contentView.scroll(to: contentView.constrainBoundsRect(bounds).origin)
        reflectScrolledClipView(contentView)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragStart = nil
        NSCursor.pop()
    }

    /// The clip's origin after dragging from one window point to another:
    /// the image follows the hand, so the origin moves the other way, in
    /// image points.
    static func dragOrigin(start: NSPoint, from: NSPoint, to: NSPoint, magnification: CGFloat) -> NSPoint {
        let scale = max(magnification, 0.0001)
        return NSPoint(x: start.x - (to.x - from.x) / scale, y: start.y - (to.y - from.y) / scale)
    }
}
