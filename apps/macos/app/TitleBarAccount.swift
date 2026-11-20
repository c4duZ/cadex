import AppKit
import Icons
import Menus
import Strings
import UILooks

/// The account on the title bar's right (the owner, 2026-11-18, after the Zed and JetBrains
/// toolbars and the AI usage meters): the provider's logo (ADR 0020), the account's name, a thin
/// bar of how much of its limit it used and the number (green, amber from 70 %, red from 90 %, as
/// the usage card's bars). The focused agent's account, else the active one; a click runs
/// agents.switch-account. Hidden with no account to say. (A gauge icon, then a ring, read as a
/// loose label and as a mouse's battery, the owner said.)
final class TitleBarAccount: NSView {
    typealias Look = DesignTokens.TitleIconButton

    var onPress: (() -> Void)?
    private let logo = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let bar = UsageBar()
    private let number = NSTextField(labelWithString: "")
    private var hovered = false { didSet { restyle() } }
    private var pressed = false { didSet { restyle() } }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(Look.radius)
        label.font = UILooks.font(DesignTokens.Breadcrumb.fontSize)
        label.lineBreakMode = .byTruncatingTail
        // A long name ("Liderhub Development", an e-mail) no wider than a tab's title; whole in the tip.
        label.widthAnchor.constraint(lessThanOrEqualToConstant: UILooks.pt(DesignTokens.Tab.maxTitle)).isActive = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        number.font = UILooks.monospacedDigits(DesignTokens.Breadcrumb.fontSize)
        let side = UILooks.pt(Look.icon)
        logo.widthAnchor.constraint(equalToConstant: side).isActive = true
        logo.heightAnchor.constraint(equalToConstant: side).isActive = true
        // As wide as two glyphs of the bar's text and as thick as the state glyph's line.
        bar.widthAnchor.constraint(equalToConstant: side * 2.5).isActive = true
        bar.heightAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Stroke.glyph) * 2).isActive = true
        let row = NSStackView(views: [logo, label, bar, number])
        row.setCustomSpacing(UILooks.pt(DesignTokens.TitleBar.gap) / 2, after: logo)
        row.spacing = UILooks.pt(DesignTokens.TitleBar.gap)
        row.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(DesignTokens.TitleBar.gap), bottom: 0, right: UILooks.pt(DesignTokens.TitleBar.gap))
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: UILooks.pt(Look.size)),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        isHidden = true
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TitleBarAccount is created in code") }

    /// The account's name and its usage when known (the bar and the number). Nil hides it.
    func show(name: String?, used: Int?, provider: ProviderLogo = .claude) {
        guard let name, !name.isEmpty else { isHidden = true; return }
        // The account's name as the rest of the app says it: the organization's, or the one the
        // owner gave it, with the folder only when two share it ("fba. + BKDG · bkdg"); cutting to
        // the part after "·" left only the folder (the owner, 2026-11-18).
        logo.image = provider.image(size: UILooks.pt(Look.icon))
        label.stringValue = name
        bar.share = used.map { Double($0) / 100 }
        bar.color = Self.color(used)
        bar.isHidden = used == nil
        number.stringValue = used.map { "\($0)%" } ?? ""
        number.textColor = (used ?? 0) >= Self.warn ? bar.color : Look.Inactive.color
        number.isHidden = used == nil
        let usage = used.map { T("\($0)% of its limit used", "\($0)% do limite usado") } ?? T("no usage read yet", "uso ainda não lido")
        let tip = name + "\n" + usage + "\n" + T("Click to switch account", "Clique para trocar de conta")
        HoverTip.attach(tip, to: self)
        setAccessibilityLabel(tip)
        isHidden = false
    }

    /// From here the bar and the number turn amber; red from `alarm` (the usage card's).
    static let warn = 70, alarm = 90

    static func color(_ used: Int?) -> NSColor {
        guard let used else { return DesignTokens.Color.textSeparator }
        return used >= alarm ? DesignTokens.Color.stateFailed : used >= warn ? DesignTokens.Color.stateNeeds : DesignTokens.Color.stateDone
    }

    private func restyle() {
        let lit = hovered || pressed
        layer?.backgroundColor = lit ? Look.Active.bg.cgColor : nil
        label.textColor = lit ? Look.Active.color : Look.Inactive.color
        logo.contentTintColor = lit ? Look.Active.color : Look.Inactive.color
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

/// A thin rounded bar filled from the left with `share` (0…1) in `color`, over a faint track.
final class UsageBar: NSView {
    var share: Double? { didSet { needsDisplay = true } }
    var color: NSColor = DesignTokens.Color.stateDone { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        DesignTokens.Color.lineControl.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        guard let share, share > 0 else { return }
        color.setFill()
        let width = max(bounds.width * min(share, 1), bounds.height)
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: bounds.height), xRadius: radius, yRadius: radius).fill()
    }
}
