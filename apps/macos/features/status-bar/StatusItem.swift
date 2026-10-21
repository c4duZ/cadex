import AppKit
import Icons
import Menus
import UILooks

/// One piece of the status bar (docs/spec/status-bar.md): the folder, the
/// environment, RAM, CPU... The app fills the catalog with each item's view
/// and data; the bar places the shown ones, left or right, and tells each
/// item when it can be seen, so a hidden one measures nothing (the owner's
/// rule, 2026-10-21).
@MainActor
public final class StatusItem {
    public enum Side: String, Sendable { case left, right }

    /// Stable, in English: "folder", "ram". The value saved in settings.json.
    public let id: String
    public let title: String
    /// What it shows and how often, for the Customize window.
    public let subtitle: String?
    public let icon: Icon?
    /// Where it goes when shown for the first time.
    public let side: Side
    public let view: NSView
    /// Seen or not: shown in the bar and the window on screen. The item
    /// starts its readings on true and stops them on false.
    public var onVisible: ((Bool) -> Void)?
    public private(set) var isVisible = false

    public init(id: String, title: String, subtitle: String? = nil, icon: Icon? = nil, side: Side = .right, view: NSView) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.side = side
        self.view = view
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        onVisible?(visible)
    }
}

/// An item's look: a Phosphor icon and a short text, in the bar's quiet
/// color; a click runs `onClick` (a command, from the app).
@MainActor
public final class StatusLabel: NSView {
    public var onClick: (() -> Void)?
    public var text = "" { didSet { if text != oldValue { label.stringValue = text; invalidateIntrinsicContentSize() } } }
    /// The text in the accent or a warning color; nil for the quiet one.
    public var tint: NSColor? { didSet { restyle() } }
    var color: NSColor = .secondaryLabelColor { didSet { restyle() } }
    private let icon: NSImageView?
    private let label = NSTextField(labelWithString: "")

    public init(icon: Icon?, tip: String? = nil) {
        self.icon = icon.map { NSImageView(image: $0.image(size: UILooks.pt(12))) }
        super.init(frame: .zero)
        label.font = UILooks.monospacedDigits(11)
        label.lineBreakMode = .byTruncatingTail
        let views = [self.icon, label].compactMap { $0 }
        let stack = NSStackView(views: views)
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: UILooks.pt(20)),
        ])
        HoverTip.attach(tip, to: self)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("StatusLabel is created in code") }

    /// The words read on hover (RAM's free part, each SSH host).
    public func setTip(_ tip: String?) {
        HoverTip.attach(tip, to: self)
        setAccessibilityLabel(tip ?? text)
    }

    override public func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override public func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    private func restyle() {
        label.textColor = tint ?? color
        icon?.contentTintColor = tint ?? color
    }
}
