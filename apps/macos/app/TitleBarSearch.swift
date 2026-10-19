import AppKit
import Icons

/// The search of the title bar as a real field, as VS Code's command center:
/// a filled, bordered box with the magnifier, the words and the ⌘K key on
/// the right. Clicking opens the palette (palette.open). As plain words it
/// read as a label, not as the way into everything (owner, 2026-10-19).
final class TitleBarSearch: NSView {
    static let height: CGFloat = 28

    var onPress: (() -> Void)?
    private let icon = NSImageView(image: Icon.magnifyingGlass.image(size: 13))
    private let label = NSTextField(labelWithString: "Buscar arquivos e comandos")
    private let key = NSTextField(labelWithString: "⌘K")
    private var colors: (text: NSColor, secondary: NSColor, field: NSColor) = (.labelColor, .secondaryLabelColor, .controlBackgroundColor)
    private var hovered = false { didSet { restyle() } }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        toolTip = "Buscar arquivos e comandos (⌘K)"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Buscar arquivos e comandos")
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        key.font = .systemFont(ofSize: 11, weight: .medium)
        for v in [icon, label, key] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            key.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
            key.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            key.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TitleBarSearch is created in code") }

    func setColors(text: NSColor, secondary: NSColor, field: NSColor) {
        colors = (text, secondary, field)
        restyle()
    }

    private func restyle() {
        layer?.backgroundColor = (hovered ? colors.field.blended(withFraction: 0.06, of: colors.text) : colors.field)?.cgColor
        layer?.borderColor = colors.text.withAlphaComponent(hovered ? 0.22 : 0.12).cgColor
        icon.contentTintColor = colors.secondary
        label.textColor = colors.secondary
        key.textColor = colors.secondary.withAlphaComponent(0.8)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
