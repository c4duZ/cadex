import AppKit
import Icons

/// A control of the title bar: an icon, words, or both, in a 26 pt rounded
/// area that lights up under the pointer and when pressed, like the tabs
/// next to it. The bare icon buttons gave no feedback and could only be hit
/// on their 16 pt glyph (UI review, 2026-10-19).
final class TitleBarButton: NSView {
    static let height: CGFloat = 26
    static let iconOnlyWidth: CGFloat = 28

    var onPress: (() -> Void)?
    var colors: (text: NSColor, secondary: NSColor) = (.labelColor, .secondaryLabelColor) { didSet { restyle() } }
    private let icon: NSImageView?
    private let label = NSTextField(labelWithString: "")
    private var hovered = false { didSet { restyle() } }
    private var pressed = false { didSet { restyle() } }
    /// Words in their own colors (the space's breadcrumb), instead of `title`.
    var attributedTitle: NSAttributedString? { didSet { restyle() } }

    init(icon: Icon?, title: String? = nil, tip: String) {
        // 15 pt alone, 13 pt next to words: one size per role.
        self.icon = icon.map { NSImageView(image: $0.image(size: title == nil ? 15 : 13)) }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        toolTip = tip
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title ?? tip)
        label.stringValue = title ?? ""
        label.font = .systemFont(ofSize: 12)
        let views: [NSView] = (self.icon.map { [$0] } ?? []) + (title == nil ? [] : [label])
        let content = NSStackView(views: views)
        content.spacing = 5
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        var constraints = [
            heightAnchor.constraint(equalToConstant: Self.height),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        if title == nil {
            constraints += [widthAnchor.constraint(equalToConstant: Self.iconOnlyWidth),
                            content.centerXAnchor.constraint(equalTo: centerXAnchor)]
        } else {
            constraints += [content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9)]
        }
        NSLayoutConstraint.activate(constraints)
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TitleBarButton is created in code") }

    /// The words; empty leaves the icon alone.
    func setTitle(_ attributed: NSAttributedString) {
        attributedTitle = attributed
        label.isHidden = attributed.length == 0
        if attributed.length > 0 { setAccessibilityLabel(attributed.string) }
    }

    private func restyle() {
        let fill: CGFloat = pressed ? 0.16 : hovered ? 0.09 : 0
        layer?.backgroundColor = fill > 0 ? colors.text.withAlphaComponent(fill).cgColor : nil
        let tint = hovered || pressed ? colors.text : colors.secondary
        icon?.contentTintColor = tint
        if let attributedTitle {
            label.attributedStringValue = attributedTitle
        } else {
            label.textColor = tint
        }
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    /// Clicks press the button; they must not drag the window.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) { pressed = true }

    override func mouseUp(with event: NSEvent) {
        pressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
