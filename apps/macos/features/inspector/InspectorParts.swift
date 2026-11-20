import AppKit
import Icons
import UILooks

/// A tab of the column (components.inspector.iconTabs.tab; docs/adr/0038-rail-and-side-column.md):
/// the page's icon in a 40×30 box, lit with the selected background when it is the one showing,
/// muted otherwise; the page's name under the pointer. The click runs the tab's command.
@MainActor
final class InspectorTabButton: NSView {
    typealias T = DesignTokens.Inspector.IconTabs.Tab
    let id: String
    let title: String
    var onPress: (() -> Void)?
    private let glyph = NSImageView()
    private let icon: Icon
    private var hovering = false { didSet { restyle() } }

    init(id: String, title: String, icon: Icon) {
        self.id = id
        self.title = title
        self.icon = icon
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(T.radius)
        glyph.image = icon.fittedImage(size: UILooks.pt(T.icon))
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: UILooks.pt(T.width)),
            heightAnchor.constraint(equalToConstant: UILooks.pt(T.height)),
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        toolTip = title
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("InspectorTabButton is created in code") }

    override var mouseDownCanMoveWindow: Bool { false }
    // The first click of an inactive window is a click here too (the owner's clicks were eaten, plan 34).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var isOn = false { didSet { restyle() } }

    // The whole box takes the click: the icon's image view caught it and, in a window not yet
    // key, ate the first one (plan 36 phase A, a click on Files did nothing).
    override func hitTest(_ point: NSPoint) -> NSView? {
        !isHidden && frame.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }

    private func restyle() {
        layer?.backgroundColor = isOn || hovering ? T.Active.bg.cgColor : nil
        glyph.contentTintColor = isOn || hovering ? T.Active.color : T.Inactive.color
    }
}

/// A button of the scope row (components.inspector.scope.button): an icon in a 24 pt box, lit
/// under the pointer like the title bar's buttons.
@MainActor
final class InspectorIconButton: NSView {
    typealias B = DesignTokens.Inspector.Scope.Button
    let command: String
    var onPress: (() -> Void)?
    private let glyph = NSImageView()
    private var hovering = false { didSet { restyle() } }

    init(command: String, icon: Icon, tip: String) {
        self.command = command
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(B.radius)
        glyph.image = icon.image(size: UILooks.pt(B.icon))
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: UILooks.pt(B.size)),
            heightAnchor.constraint(equalToConstant: UILooks.pt(B.size)),
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        // Its own size in the scope row: the words take what is left, so the buttons sit right.
        setContentHuggingPriority(.required, for: .horizontal)
        toolTip = tip
        setAccessibilityRole(.button)
        setAccessibilityLabel(tip)
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("InspectorIconButton is created in code") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }

    private func restyle() {
        typealias Lit = DesignTokens.TitleIconButton.Active
        layer?.backgroundColor = hovering ? Lit.bg.cgColor : nil
        glyph.contentTintColor = hovering ? Lit.color : B.color
    }
}
