import AppKit
import Icons
import Menus
import Strings
import UILooks

/// The account on the title bar's right (the owner, 2026-11-18, after the Zed and JetBrains
/// toolbars): the gauge, the focused agent's account (else the active one) and how much of its
/// limit it used, in the title buttons' look; a click runs agents.switch-account. Hidden with no
/// account to say.
final class TitleBarAccount: NSView {
    typealias Look = DesignTokens.TitleIconButton

    var onPress: (() -> Void)?
    private let icon = NSImageView(image: Icon.gauge.image(size: UILooks.pt(DesignTokens.TitleIconButton.icon)))
    private let label = NSTextField(labelWithString: "")
    private var hovered = false { didSet { restyle() } }
    private var pressed = false { didSet { restyle() } }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(Look.radius)
        label.font = UILooks.font(DesignTokens.Breadcrumb.fontSize)
        label.lineBreakMode = .byTruncatingTail
        let row = NSStackView(views: [icon, label])
        row.spacing = UILooks.pt(DesignTokens.TitleBar.gap)
        row.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(DesignTokens.TitleBar.gap), bottom: 0, right: UILooks.pt(DesignTokens.TitleBar.gap))
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: UILooks.pt(Look.size)),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        let tip = T("Switch account", "Trocar de conta")
        HoverTip.attach(tip, to: self)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tip)
        isHidden = true
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TitleBarAccount is created in code") }

    /// "bkdg · 32%"; the account's short name (the part after its organization's), the usage when
    /// known. Nil hides it.
    func show(name: String?, used: Int?) {
        guard let name, !name.isEmpty else { isHidden = true; return }
        let short = name.components(separatedBy: " · ").last ?? name
        label.stringValue = [short, used.map { "\($0)%" }].compactMap { $0 }.joined(separator: " · ")
        isHidden = false
    }

    private func restyle() {
        let lit = hovered || pressed
        layer?.backgroundColor = lit ? Look.Active.bg.cgColor : nil
        icon.contentTintColor = lit ? Look.Active.color : Look.Inactive.color
        label.textColor = lit ? Look.Active.color : Look.Inactive.color
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
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
