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
    public var onClick: (() -> Void)? { didSet { if onClick != nil { HoverHighlight.attach(self) } } }
    public var text = "" {
        didSet {
            guard text != oldValue else { return }
            if !oldValue.isEmpty { SlidingStack.fade(label) }
            label.stringValue = text
            invalidateIntrinsicContentSize()
        }
    }
    /// A longer text is cut with "…" (the whole of it in the tip): a very
    /// long branch pushed the whole bar (the owner, 2026-10-22).
    public var maxTextWidth: CGFloat? {
        didSet {
            textCap?.isActive = false
            textCap = maxTextWidth.map { label.widthAnchor.constraint(lessThanOrEqualToConstant: $0) }
            textCap?.isActive = true
        }
    }
    private var textCap: NSLayoutConstraint?
    /// The text in the accent or a warning color; nil for the quiet one.
    public var tint: NSColor? { didSet { restyle() } }
    var color: NSColor = DesignTokens.StatusBar.color { didSet { restyle() } }
    /// A state's dot before the text ("● 3 working", the mockup's StatusBar); nil hides it.
    public var dot: NSColor? { didSet { restyle() } }
    private let icon: NSImageView?
    private let dotView = NSView()
    private let label = NSTextField(labelWithString: "")

    public init(icon: Icon?, tip: String? = nil) {
        typealias Look = DesignTokens.StatusBar
        self.icon = icon.map { NSImageView(image: $0.image(size: UILooks.pt(Look.icon))) }
        super.init(frame: .zero)
        label.font = UILooks.monospacedDigits(Look.fontSize)
        label.lineBreakMode = .byTruncatingTail
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = UILooks.pt(Look.dot) / 2
        dotView.isHidden = true
        let views = [self.icon, dotView, label].compactMap { $0 }
        let stack = NSStackView(views: views)
        stack.spacing = UILooks.pt(Look.iconGap)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: StatusBarView.itemInset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -StatusBarView.itemInset),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: UILooks.pt(Look.itemHeight)),
            dotView.widthAnchor.constraint(equalToConstant: UILooks.pt(Look.dot)),
            dotView.heightAnchor.constraint(equalToConstant: UILooks.pt(Look.dot)),
        ])
        HoverTip.attach(tip, to: self)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("StatusLabel is created in code") }

    /// Another icon, in its fill weight when `filled` (the coffee while keeping awake).
    public func setIcon(_ kind: Icon, filled: Bool) {
        icon?.image = kind.image(size: UILooks.pt(DesignTokens.StatusBar.icon), filled: filled)
    }

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
        dotView.isHidden = dot == nil
        dotView.layer?.backgroundColor = dot?.cgColor
    }
}
