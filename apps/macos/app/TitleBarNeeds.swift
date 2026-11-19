import AppKit
import UILooks

/// The needs-you pill of the top bar (components.place.needs; ADR 0039): shown only with the sidebar
/// closed, it says who waits ("checkout-copy needs you"); the click goes there (agents.go-to-request).
@MainActor
final class TitleBarNeeds: NSView {
    typealias N = DesignTokens.Place.Needs
    var onPress: (() -> Void)?
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = N.bg.cgColor
        layer?.borderColor = N.border.cgColor
        layer?.borderWidth = DesignTokens.Stroke.hairline
        layer?.cornerRadius = UILooks.pt(N.radius)
        label.font = UILooks.font(N.fontSize, weight: N.weight)
        label.textColor = N.color
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: UILooks.pt(N.height)),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(N.padding.left)),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(N.padding.right)),
        ])
        setAccessibilityRole(.button)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TitleBarNeeds is created in code") }

    func say(_ text: String?) {
        label.stringValue = text ?? ""
        setAccessibilityLabel(text)
        isHidden = text == nil
    }

    var said: String { label.stringValue }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }
}
