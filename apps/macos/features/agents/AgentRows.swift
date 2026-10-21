import AppKit
import Icons
import UILooks

/// The page's colors, from the theme: text, quiet text, the accent (a
/// working agent's ring, a project's folder) and the waiting dot's blue.
public struct AgentColors {
    public var text: NSColor
    public var secondary: NSColor
    public var accent: NSColor
    public var waiting: NSColor
    public var fill: NSColor
    /// The popover's ground and border, the menus' colors.
    public var panel: NSColor
    public var border: NSColor

    public init(text: NSColor = .labelColor, secondary: NSColor = .secondaryLabelColor, accent: NSColor = .controlAccentColor,
                waiting: NSColor = .systemBlue, fill: NSColor = .quaternaryLabelColor,
                panel: NSColor = .windowBackgroundColor, border: NSColor = .separatorColor) {
        self.text = text
        self.secondary = secondary
        self.accent = accent
        self.waiting = waiting
        self.fill = fill
        self.panel = panel
        self.border = border
    }
}

/// "3m", "2h", "1d": how long a session has been in its status.
enum AgentTime {
    static func short(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
    }
}

/// A session's sign: a turning ring while it works, a dot while it waits
/// for an answer, a grey dot for a status the page does not know.
@MainActor
final class AgentSign: NSView {
    enum Kind { case working, waiting, done, unknown }

    private let shape = CAShapeLayer()

    init(_ kind: Kind, colors: AgentColors, size: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        shape.frame = bounds
        layer?.addSublayer(shape)
        let inset = size * 0.15
        let box = bounds.insetBy(dx: inset, dy: inset)
        switch kind {
        case .working:
            shape.path = CGPath(ellipseIn: box, transform: nil)
            shape.fillColor = nil
            shape.strokeColor = colors.accent.cgColor
            shape.lineWidth = max(1.5, size * 0.16)
            shape.strokeEnd = 0.72
            shape.lineCap = .round
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -2 * Double.pi
            spin.duration = 1
            spin.repeatCount = .infinity
            shape.add(spin, forKey: "spin")
        case .waiting, .unknown:
            shape.path = CGPath(ellipseIn: box.insetBy(dx: size * 0.08, dy: size * 0.08), transform: nil)
            shape.fillColor = (kind == .waiting ? colors.waiting : colors.secondary).cgColor
        case .done:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: box.minX, y: box.midY))
            path.addLine(to: CGPoint(x: box.minX + box.width * 0.38, y: box.minY + box.height * 0.2))
            path.addLine(to: CGPoint(x: box.maxX, y: box.maxY - box.height * 0.1))
            shape.path = path
            shape.fillColor = nil
            shape.strokeColor = NSColor.systemGreen.cgColor
            shape.lineWidth = 1.6
            shape.lineCap = .round
        }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: size), heightAnchor.constraint(equalToConstant: size)])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AgentSign is created in code") }
}

/// A row of the page that answers clicks: one click and a double click.
@MainActor
final class AgentRow: NSView {
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var fill: NSColor? { didSet { restyle() } }
    /// The soft fill under the pointer, for rows that do something on a click.
    var hoverFill: NSColor? {
        didSet {
            trackingAreas.forEach(removeTrackingArea)
            if hoverFill != nil {
                addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
            }
        }
    }
    private var hovering = false { didSet { if hovering != oldValue { restyle(animated: true) } } }
    private var pressed = false { didSet { if pressed != oldValue { restyle(animated: !pressed) } } }

    /// The fill fades in 0.12 s under the pointer and darkens at once on a
    /// press: a click that changed the colour later felt stuck (the owner,
    /// 2026-10-21).
    private func restyle(animated: Bool = false) {
        var color = hovering ? hoverFill ?? fill : fill
        if pressed, let hoverFill { color = hoverFill.withAlphaComponent(min(1, hoverFill.alphaComponent * 1.8)) }
        guard let layer else { return }
        if animated {
            let fade = CABasicAnimation(keyPath: "backgroundColor")
            fade.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
            fade.duration = 0.12
            layer.add(fade, forKey: "fill")
        }
        layer.backgroundColor = color?.cgColor
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false; pressed = false }

    /// A list drawn again under a still pointer: the row there starts lit,
    /// as it would after a move.
    override func layout() {
        super.layout()
        guard hoverFill != nil, !checkedPointer, let window, bounds.width > 0 else { return }
        checkedPointer = true
        if bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) { hovering = true; restyle() }
    }
    private var checkedPointer = false

    init(_ content: NSView, inset: CGFloat = 6) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AgentRow is created in code") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func rightMouseDown(with event: NSEvent) {
        if let onRightClick { onRightClick() } else { super.rightMouseDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        if onClick != nil || onDoubleClick != nil { pressed = true }
    }

    override func mouseUp(with event: NSEvent) {
        pressed = false
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        if event.clickCount == 2 { onDoubleClick?() } else if event.clickCount == 1 { onClick?() }
    }
}

/// Text helpers for the rows.
@MainActor
enum AgentText {
    static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = UILooks.font(size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    static func icon(_ icon: Icon, size: CGFloat, color: NSColor) -> NSImageView {
        let view = NSImageView(image: icon.image(size: UILooks.pt(size)))
        view.contentTintColor = color
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }
}
