import AppKit

/// A rounded panel inside the window frame: the sidebar and
/// the terminal area. Clips what it holds to its corners.
final class PanelView: NSView {
    static let cornerRadius: CGFloat = 8

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.masksToBounds = true
        layer?.borderWidth = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelView is created in code") }

    func setColors(fill: NSColor, border: NSColor) {
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = border.cgColor
    }
}
