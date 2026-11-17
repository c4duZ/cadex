import AppKit
import UILooks
import Icons
import Menus

/// An icon button of the title bar (components.titleIconButton of the new frame's tokens,
/// docs/adr/0035-work-frame.md): 30 pt, rounded, the icon in the secondary text and lit with the
/// chip's fill while what it opens is open (the right panel, the bell's popover), or under the
/// pointer and when pressed. A badge in the needs-you amber carries a count (the bell).
final class TitleBarButton: NSView {
    typealias Look = DesignTokens.TitleIconButton

    /// The bar's buttons, and the smaller "+" after the tabs (components.tab.add).
    @MainActor enum Kind {
        case standard, add
        var size: CGFloat { UILooks.pt(self == .add ? DesignTokens.Tab.Add.size : Look.size) }
        var icon: CGFloat { UILooks.pt(self == .add ? DesignTokens.Tab.Add.glyph : Look.icon) }
        var rest: NSColor { self == .add ? DesignTokens.Tab.Add.color : Look.Inactive.color }
    }

    var onPress: (() -> Void)?
    /// A right click; nil leaves it to the window.
    var onRightPress: (() -> Void)?
    /// What the button opens is open: the chip's fill and the primary text.
    var isOn = false { didSet { restyle() } }
    /// Another color than the secondary text at rest: the update is news, in the accent.
    var tint: NSColor? { didSet { restyle() } }
    private let kind: Kind
    private let icon: NSImageView
    private let iconKind: Icon
    /// The badge: a round box with the count centered in it (a label alone sits high).
    private let badge = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private var hovered = false { didSet { restyle() } }
    private var pressed = false { didSet { restyle() } }

    init(icon: Icon, tip: String, kind: Kind = .standard) {
        self.kind = kind
        iconKind = icon
        self.icon = NSImageView(image: icon.image(size: kind.icon))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(Look.radius)
        HoverTip.attach(tip, to: self)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tip)
        for view in [self.icon, badge] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        badgeLabel.font = UILooks.font(DesignTokens.Badge.fontSize, weight: DesignTokens.Badge.weight)
        badgeLabel.alignment = .center
        badgeLabel.textColor = DesignTokens.Badge.color
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(badgeLabel)
        badge.wantsLayer = true
        badge.layer?.backgroundColor = DesignTokens.Badge.bg.cgColor
        badge.layer?.cornerRadius = UILooks.pt(DesignTokens.Badge.radius)
        badge.isHidden = true
        let side = kind.size
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: side),
            heightAnchor.constraint(equalToConstant: side),
            self.icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            self.icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(DesignTokens.Badge.top)),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(DesignTokens.Badge.right)),
            badge.heightAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Badge.height)),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: UILooks.pt(DesignTokens.Badge.minWidth)),
            badge.widthAnchor.constraint(greaterThanOrEqualTo: badgeLabel.widthAnchor),
            badgeLabel.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
        ])
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TitleBarButton is created in code") }

    /// The count on the badge; nil or zero hides it.
    func setBadge(_ count: Int?) {
        let shown = (count ?? 0) > 0
        badge.isHidden = !shown
        badgeLabel.stringValue = shown ? "\(count!)" : ""
    }

    /// The icon again in its fill weight (keep-awake on).
    func setFilled(_ filled: Bool) {
        icon.image = iconKind.image(size: kind.icon, filled: filled)
    }

    private func restyle() {
        let lit = isOn || hovered || pressed
        layer?.backgroundColor = lit ? Look.Active.bg.cgColor : nil
        icon.contentTintColor = tint ?? (lit ? Look.Active.color : kind.rest)
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Only its own: removing them all took the hover tip's away (owner, 2026-10-20).
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; TitleBarHold.entered(self) }
    override func mouseExited(with event: NSEvent) { hovered = false; TitleBarHold.exited(self, holding: pressed) }
    /// Clicks press the button; they must not drag the window.
    override var mouseDownCanMoveWindow: Bool { false }

    override func rightMouseDown(with event: NSEvent) {
        if let onRightPress { onRightPress() } else { super.rightMouseDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) { pressed = true }

    override func mouseUp(with event: NSEvent) {
        pressed = false
        TitleBarHold.released(self, event)
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
