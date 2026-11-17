import AppKit
import Icons
import UILooks

/// A tab's name in the row (components.inspector.tabs.tab): semibold and underlined when it is
/// the one showing, muted otherwise; the click runs the tab's command.
@MainActor
final class InspectorTabButton: NSView {
    typealias T = DesignTokens.Inspector.Tabs.Tab
    let id: String
    var onPress: (() -> Void)?
    private let label = NSTextField(labelWithString: "")
    private let underline = NSView()

    init(id: String, title: String) {
        self.id = id
        super.init(frame: .zero)
        label.stringValue = title
        underline.wantsLayer = true
        underline.layer?.backgroundColor = T.Active.color.cgColor
        for view in [label, underline] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(T.padding.top)),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -UILooks.pt(T.padding.bottom)),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(T.padding.left)),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(T.padding.right)),
            underline.leadingAnchor.constraint(equalTo: leadingAnchor),
            underline.trailingAnchor.constraint(equalTo: trailingAnchor),
            underline.bottomAnchor.constraint(equalTo: bottomAnchor),
            underline.heightAnchor.constraint(equalToConstant: T.Active.underline),
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        isOn = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("InspectorTabButton is created in code") }

    override var mouseDownCanMoveWindow: Bool { false }

    var isOn = false {
        didSet {
            label.font = isOn ? UILooks.font(T.fontSize, weight: T.Active.weight) : UILooks.font(T.fontSize)
            label.textColor = isOn ? T.Active.color : T.Inactive.color
            underline.isHidden = !isOn
        }
    }

    var title: String { label.stringValue }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
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
