import AppKit
import Icons
import Menus
import UILooks

/// One icon of the row: the glyph, filled while its page shows, and an
/// optional mark on the corner (a count, or a dot when the text is empty).
/// Clicks and drags go up to the row, which tells a press from a drag.
@MainActor
final class SidebarIconButton: NSView {
    static var size: NSSize { NSSize(width: UILooks.pt(30), height: UILooks.pt(28)) }

    let id: String
    var selected = false { didSet { restyle() } }
    var colors: SidebarColors = .init() { didSet { restyle() } }
    /// "3" draws a small count, "" a dot, nil nothing.
    var badge: String? { didSet { restyleBadge() } }
    var onPress: (() -> Void)?
    private let icon: NSImageView
    private let badgeLabel = NSTextField(labelWithString: "")
    private var hovering = false { didSet { restyle() } }

    init(id: String, icon: Icon, tip: String) {
        self.id = id
        self.icon = NSImageView(image: icon.fittedImage(size: UILooks.pt(16)))
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        layer?.cornerRadius = 6
        HoverTip.attach(tip, to: self)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tip)
        addSubview(self.icon)
        badgeLabel.font = UILooks.monospacedDigits(8.5, weight: .semibold)
        badgeLabel.alignment = .center
        badgeLabel.wantsLayer = true
        badgeLabel.isHidden = true
        addSubview(badgeLabel)
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SidebarIconButton is created in code") }

    override func layout() {
        super.layout()
        let side = UILooks.pt(16)
        icon.frame = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        let dot = badge?.isEmpty == true
        let h = dot ? UILooks.pt(7) : UILooks.pt(12)
        let w = dot ? h : max(h, badgeLabel.intrinsicContentSize.width + UILooks.pt(4))
        badgeLabel.frame = NSRect(x: bounds.width - w - UILooks.pt(2), y: bounds.height - h - UILooks.pt(2), width: w, height: h)
        badgeLabel.layer?.cornerRadius = h / 2
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    private func restyle() {
        let fill = selected ? colors.fill : hovering ? colors.fill.withAlphaComponent(0.5) : nil
        layer?.backgroundColor = fill?.cgColor
        icon.contentTintColor = selected ? colors.accent : hovering ? colors.text : colors.secondary
        restyleBadge()
    }

    private func restyleBadge() {
        badgeLabel.isHidden = badge == nil
        badgeLabel.stringValue = badge ?? ""
        badgeLabel.textColor = colors.accent
        badgeLabel.layer?.backgroundColor = (badge?.isEmpty == true ? colors.accent : colors.fill).cgColor
        needsLayout = true
    }
}

/// The theme's colors for the sidebar: text, quiet text, the chosen fill
/// and the accent.
public struct SidebarColors {
    public var text: NSColor
    public var secondary: NSColor
    public var fill: NSColor
    public var accent: NSColor

    public init(text: NSColor = .labelColor, secondary: NSColor = .secondaryLabelColor,
                fill: NSColor = .quaternaryLabelColor, accent: NSColor = .controlAccentColor) {
        self.text = text
        self.secondary = secondary
        self.fill = fill
        self.accent = accent
    }
}
