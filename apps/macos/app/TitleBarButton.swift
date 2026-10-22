import AppKit
import UILooks
import Icons
import Menus

/// A control of the title bar: an icon, words, or both, in a 26 pt rounded
/// area that lights up under the pointer and when pressed, like the tabs
/// next to it. The bare icon buttons gave no feedback and could only be hit
/// on their 16 pt glyph (UI review, 2026-10-19).
final class TitleBarButton: NSView {
    static var height: CGFloat { UILooks.pt(26) }
    static var iconSize: CGFloat { UILooks.pt(15) }
    /// The same margin on both sides of every button, with words or not, so
    /// icons side by side sit at equal distances: an icon alone is 28 pt.
    /// Mixed margins (8 and 9 pt next to a 28 pt icon button) left the
    /// group's gaps uneven (owner, 2026-10-19).
    static var margin: CGFloat { UILooks.pt(6.5) }
    static var iconOnlyWidth: CGFloat { iconSize + margin * 2 }

    var onPress: (() -> Void)?
    /// A right click; nil leaves it to the window.
    var onRightPress: (() -> Void)?
    var colors: (text: NSColor, secondary: NSColor) = (.labelColor, .secondaryLabelColor) { didSet { restyle() } }
    private let icon: NSImageView?
    private let label = NSTextField(labelWithString: "")
    private var hovered = false { didSet { restyle() } }
    private var pressed = false { didSet { restyle() } }
    /// Words in their own colors (the space's breadcrumb), instead of `title`.
    var attributedTitle: NSAttributedString? { didSet { restyle() } }

    init(icon: Icon?, title: String? = nil, tip: String) {
        self.icon = icon.map { NSImageView(image: $0.image(size: Self.iconSize)) }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        HoverTip.attach(tip, to: self)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title ?? tip)
        label.stringValue = title ?? ""
        label.font = UILooks.font(12)
        let views: [NSView] = (self.icon.map { [$0] } ?? []) + (title == nil ? [] : [label])
        let content = NSStackView(views: views)
        content.spacing = 4
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        var constraints = [
            heightAnchor.constraint(equalToConstant: Self.height),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        if title == nil {
            constraints += [widthAnchor.constraint(equalToConstant: Self.iconOnlyWidth),
                            content.centerXAnchor.constraint(equalTo: centerXAnchor)]
        } else {
            constraints += [content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.margin),
                            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.margin)]
        }
        NSLayoutConstraint.activate(constraints)
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TitleBarButton is created in code") }

    /// The words; empty leaves the icon alone.
    func setTitle(_ attributed: NSAttributedString) {
        attributedTitle = attributed
        label.isHidden = attributed.length == 0
        if attributed.length > 0 { setAccessibilityLabel(attributed.string) }
    }

    /// Another icon, the fill weight when `filled` (keep-awake on).
    func setIcon(_ icon: Icon, filled: Bool) {
        self.icon?.image = icon.image(size: Self.iconSize, filled: filled)
    }

    private func restyle() {
        let fill: CGFloat = pressed ? 0.16 : hovered ? 0.09 : 0
        layer?.backgroundColor = fill > 0 ? colors.text.withAlphaComponent(fill).cgColor : nil
        let tint = hovered || pressed ? colors.text : colors.secondary
        icon?.contentTintColor = tint
        if let attributedTitle {
            label.attributedStringValue = attributedTitle
        } else {
            label.textColor = tint
        }
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Only its own: removing them all took the hover tip's away (the
        // title bar showed no names, owner, 2026-10-20).
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
