import AppKit

/// Tells when the mouse goes down anywhere in a pane, its subviews too,
/// without taking the click: it fails at once, so the view under the
/// pointer gets the press, the drag and the release as before. A click
/// recognizer would miss presses that become drags (selecting text).
final class PanePressRecognizer: NSGestureRecognizer {
    var onPress: (() -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delaysPrimaryMouseButtonEvents = false
        delaysSecondaryMouseButtonEvents = false
    }

    convenience init() { self.init(target: nil, action: nil) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanePressRecognizer is created in code") }

    override func mouseDown(with event: NSEvent) {
        onPress?()
        state = .failed
    }

    override func rightMouseDown(with event: NSEvent) {
        onPress?()
        state = .failed
    }
}
