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

    /// `inset` and `trailing` keep the content off the sides, `vertical` off the top and bottom
    /// (the bell's lines give their own: its rows are 34 pt with nothing around, Bell mockup).
    init(_ content: NSView, inset: CGFloat = 6, trailing: CGFloat = 6, vertical: CGFloat = 5) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: vertical),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vertical),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -trailing),
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
