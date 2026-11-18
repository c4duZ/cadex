import AppKit

/// A filter's pill (components.board.filters.pill): the chosen one filled, the others outlined,
/// the title centered in its height. The board's filters (plan 30 B) and the archive's scope and
/// grouping (plan 31 C) use it, so it lives here.
@MainActor
public enum FramePill {
    public static func make(_ title: String, on: Bool, run: @escaping @MainActor () -> Void) -> NSView {
        typealias P = DesignTokens.Board.Filters.Pill
        let pill = FramePillView()
        pill.wantsLayer = true
        pill.layer?.cornerRadius = UILooks.pt(P.height) / 2
        pill.layer?.backgroundColor = on ? P.Active.bg.cgColor : nil
        pill.layer?.borderColor = on ? nil : P.Inactive.border.cgColor
        pill.layer?.borderWidth = on ? 0 : DesignTokens.Stroke.hairline
        let label = NSTextField(labelWithString: title)
        label.font = UILooks.font(P.fontSize, weight: on ? P.Active.weight : .regular)
        label.textColor = on ? P.Active.color : P.Inactive.color
        // Centered in the pill's height (pinned to the top it sat high, 2026-11-17).
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: UILooks.pt(P.padding.left)),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -UILooks.pt(P.padding.right)),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: UILooks.pt(P.height)),
        ])
        pill.onPress = run
        pill.setAccessibilityElement(true)
        pill.setAccessibilityRole(.button)
        pill.setAccessibilityLabel(title)
        return pill
    }
}

/// The pill's view: a click runs its closure.
@MainActor
final class FramePillView: NSView {
    var onPress: (@MainActor () -> Void)?
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }
}
