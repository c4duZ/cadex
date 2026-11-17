import AppKit

/// The center between the tree and the right panel: the window's ground, where the panes' boxes
/// sit (plan 28 phase B); it clips what it holds and carries the background image.
final class PanelView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelView is created in code") }

    func setColors(fill: NSColor, border: NSColor) {
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = border.cgColor
    }
}
