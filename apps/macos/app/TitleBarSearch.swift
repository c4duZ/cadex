import AppKit
import UILooks
import Icons
import Menus
import Strings

/// The title bar's search (components.search of the new frame's tokens): a quiet field that
/// says "Search ⌘K" and opens the palette, which searches files and runs every command
/// (ADR 0005). Not a text field: typing happens in the palette.
final class TitleBarSearch: NSView {
    typealias Look = DesignTokens.Search

    var onPress: (() -> Void)?
    private let glass = NSImageView(image: Icon.magnifyingGlass.image(size: UILooks.pt(Look.icon)))
    private let label = NSTextField(labelWithString: T("Search", "Buscar"))
    private let key = NSTextField(labelWithString: "⌘K")
    private var hovered = false { didSet { restyle() } }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(Look.radius)
        layer?.borderWidth = DesignTokens.Stroke.hairline
        HoverTip.attach(T("Search files and commands (⌘K)", "Buscar arquivos e comandos (⌘K)"), to: self)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(T("Search files and commands", "Buscar arquivos e comandos"))
        label.font = UILooks.font(Look.fontSize)
        key.font = UILooks.font(Look.Kbd.fontSize)
        let spacer = NSView()
        let row = NSStackView(views: [glass, label, spacer, key])
        row.spacing = UILooks.pt(Look.gap)
        row.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(Look.padding.left), bottom: 0, right: UILooks.pt(Look.padding.right))
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: UILooks.pt(Look.width)),
            heightAnchor.constraint(equalToConstant: UILooks.pt(Look.height)),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TitleBarSearch is created in code") }

    private func restyle() {
        layer?.backgroundColor = (hovered ? DesignTokens.Color.bgButton : Look.bg).cgColor
        layer?.borderColor = Look.border.cgColor
        glass.contentTintColor = Look.text
        label.textColor = Look.text
        key.textColor = Look.Kbd.color
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; TitleBarHold.entered(self) }
    override func mouseExited(with event: NSEvent) { hovered = false; TitleBarHold.exited(self, holding: false) }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        TitleBarHold.released(self, event)
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
