import AppKit
import Icons
import Menus
import Strings
import UILooks

/// The account on the title bar's right (the owner, 2026-11-18, after the Zed and JetBrains
/// toolbars): a small ring that fills with how much of its limit the account used (green, amber
/// from 70 %, red from 90 %, as the usage card's bars), then the account's name, and the number
/// only from 70 %, when it matters; the rest in the tip. The focused agent's account, else the
/// active one; a click runs agents.switch-account. Hidden with no account to say. (A gauge icon
/// and "bkdg · 0%" read as a loose label, the owner said.)
final class TitleBarAccount: NSView {
    typealias Look = DesignTokens.TitleIconButton

    var onPress: (() -> Void)?
    private let ring = UsageRing()
    private let label = NSTextField(labelWithString: "")
    private let number = NSTextField(labelWithString: "")
    private var hovered = false { didSet { restyle() } }
    private var pressed = false { didSet { restyle() } }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(Look.radius)
        label.font = UILooks.font(DesignTokens.Breadcrumb.fontSize)
        label.lineBreakMode = .byTruncatingTail
        number.font = UILooks.font(DesignTokens.Breadcrumb.fontSize)
        let side = UILooks.pt(Look.icon)
        ring.widthAnchor.constraint(equalToConstant: side).isActive = true
        ring.heightAnchor.constraint(equalToConstant: side).isActive = true
        let row = NSStackView(views: [ring, label, number])
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

    /// The account's short name (the part after its organization's) and its usage when known (the
    /// ring; the number from `warn`). Nil hides it.
    func show(name: String?, used: Int?) {
        guard let name, !name.isEmpty else { isHidden = true; return }
        let short = name.components(separatedBy: " · ").last ?? name
        label.stringValue = short
        ring.share = used.map { Double($0) / 100 }
        ring.color = Self.color(used)
        number.stringValue = used.map { $0 >= Self.warn ? "\($0)%" : "" } ?? ""
        number.textColor = ring.color
        number.isHidden = number.stringValue.isEmpty
        let usage = used.map { T("\($0)% of its limit used", "\($0)% do limite usado") } ?? T("no usage read yet", "uso ainda não lido")
        let tip = name + "\n" + usage + "\n" + T("Click to switch account", "Clique para trocar de conta")
        HoverTip.attach(tip, to: self)
        setAccessibilityLabel(tip)
        isHidden = false
    }

    /// From here the number shows and the ring turns amber; red from `alarm` (the usage card's).
    static let warn = 70, alarm = 90

    static func color(_ used: Int?) -> NSColor {
        guard let used else { return DesignTokens.Color.textSeparator }
        return used >= alarm ? DesignTokens.Color.stateFailed : used >= warn ? DesignTokens.Color.stateNeeds : DesignTokens.Color.stateDone
    }

    private func restyle() {
        let lit = hovered || pressed
        layer?.backgroundColor = lit ? Look.Active.bg.cgColor : nil
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

/// A ring that fills clockwise from the top with `share` (0…1) in `color`, over a faint track.
final class UsageRing: NSView {
    var share: Double? { didSet { needsDisplay = true } }
    var color: NSColor = DesignTokens.Color.textSeparator { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let line = max(DesignTokens.Stroke.glyph, UILooks.pt(DesignTokens.Stroke.glyph))
        let rect = bounds.insetBy(dx: line, dy: line)
        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = line
        DesignTokens.Color.lineControl.setStroke()
        track.stroke()
        guard let share, share > 0 else { return }
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: rect.width / 2, startAngle: 90, endAngle: 90 - 360 * min(share, 1), clockwise: true)
        arc.lineWidth = line
        arc.lineCapStyle = .round
        color.setStroke()
        arc.stroke()
    }
}
