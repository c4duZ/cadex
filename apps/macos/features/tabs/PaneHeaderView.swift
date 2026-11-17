import AppKit
import Icons
import StateGlyph
import Strings
import UILooks

/// The header of every pane (plan 28 phase B; the Terminals and Pane mockups,
/// components.pane.header): 34 pt, the state's glyph, the name in semibold, what it is
/// ("orchestration-e · Opus · bkdg") dimmer, and on the right the cost and the time; the line of
/// the pane under it. The "+" (what opens beside), maximize and close show under the pointer
/// only, as the mockups draw none; they keep issue #1's way to close one pane.
@MainActor
final class PaneHeaderView: NSView {
    typealias H = DesignTokens.Pane.Header
    static var height: CGFloat { UILooks.rowHeight(H.height) }

    struct Info: Equatable {
        var title: String
        var icon: Icon
        var iconColor: NSColor?
        var image: NSImage?
        var dirty = false
        /// What runs in the pane (an agent's state): the glyph before the name.
        var state: GlyphState?
        /// "orchestration-e · Opus · bkdg": where and who, after the name.
        var detail = ""
        /// "US$ 0.31 · 4 min": on the right.
        var trailing = ""
        /// A terminal: its text gets the mockup's room inside the box (components.pane.bodyPadding).
        var padded = false
        /// The pane's own bar is its header (a preview): this one is not shown.
        var hidden = false
        /// "Open :5173 in preview": the blue chip on the right (a command serving an address).
        var offer = ""
    }

    enum DragPhase { case began, moved, ended }
    enum Action { case focus, close, zoom, menu(NSView), drag(DragPhase, NSPoint), offer }

    var info = Info(title: "", icon: .terminalWindow) { didSet { if info != oldValue { refresh() } } }
    var focused = false { didSet { if focused != oldValue { refresh() } } }
    var zoomed = false { didSet { if zoomed != oldValue { refresh() } } }
    var style = TabBarView.Style(activeFill: .controlBackgroundColor, hoverFill: .quaternaryLabelColor,
                                 text: .labelColor, secondaryText: .secondaryLabelColor) { didSet { refresh() } }
    var onAction: ((Action) -> Void)?

    private let glyph = StateGlyphView(size: H.glyph)
    private let label = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let trailing = NSTextField(labelWithString: "")
    private let offer = PaneHeaderOffer()
    private let menuButton = PaneHeaderButton(icon: .plus)
    private let zoomButton = PaneHeaderButton(icon: .cornersOut)
    private let closeButton = PaneHeaderButton(icon: .x)
    private let buttons: NSStackView
    private var hovering = false { didSet { if hovering != oldValue { refresh() } } }

    override init(frame: NSRect) {
        buttons = NSStackView(views: [menuButton, zoomButton, closeButton])
        super.init(frame: frame)
        label.font = UILooks.font(H.fontSize, weight: H.name)
        for field in [label, detail, trailing] {
            field.lineBreakMode = .byTruncatingTail
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        detail.font = UILooks.font(H.fontSize)
        trailing.font = UILooks.font(H.fontSize)
        trailing.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        glyph.widthAnchor.constraint(equalToConstant: UILooks.pt(H.glyph)).isActive = true
        glyph.heightAnchor.constraint(equalToConstant: UILooks.pt(H.glyph)).isActive = true
        menuButton.onPress = { [weak self] in self.map { $0.onAction?(.menu($0.menuButton)) } }
        zoomButton.onPress = { [weak self] in self?.onAction?(.zoom) }
        closeButton.onPress = { [weak self] in self?.onAction?(.close) }
        menuButton.toolTip = T("Open Beside, Split, Maximize, Close", "Abrir ao lado, dividir, maximizar, fechar")
        buttons.spacing = UILooks.pt(DesignTokens.Stroke.glyph)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        offer.onPress = { [weak self] in self?.onAction?(.offer) }
        let row = NSStackView(views: [glyph, label, detail, spacer, offer, trailing, buttons])
        row.spacing = UILooks.pt(H.gap)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(H.padding.left)),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(H.padding.right)),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PaneHeaderView is created in code") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    /// The middle button closes the pane, as it closes a tab.
    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { onAction?(.close) } else { super.otherMouseUp(with: event) }
    }

    private var pressedAt: NSPoint?
    private var dragging = false

    override func mouseDown(with event: NSEvent) {
        pressedAt = event.locationInWindow
        dragging = false
    }

    /// Past 4 pt the press becomes a drag of the pane (PaneLayoutView.dragPane).
    override func mouseDragged(with event: NSEvent) {
        guard let start = pressedAt else { return }
        let point = event.locationInWindow
        if !dragging, hypot(point.x - start.x, point.y - start.y) > 4 {
            dragging = true
            onAction?(.drag(.began, start))
        }
        if dragging { onAction?(.drag(.moved, point)) }
    }

    /// A click focuses the pane; a double click maximizes it, as a window's
    /// title bar zooms the window; the end of a drag drops the pane.
    override func mouseUp(with event: NSEvent) {
        defer { pressedAt = nil; dragging = false }
        if dragging { return onAction?(.drag(.ended, event.locationInWindow)) ?? () }
        onAction?(event.clickCount == 2 ? .zoom : .focus)
    }

    private func refresh() {
        label.stringValue = (info.dirty ? "● " : "") + info.title
        label.textColor = DesignTokens.Color.textPrimary
        detail.stringValue = info.detail
        detail.textColor = H.meta
        detail.isHidden = info.detail.isEmpty
        trailing.stringValue = info.trailing
        trailing.textColor = H.meta
        trailing.isHidden = info.trailing.isEmpty
        offer.text = info.offer
        offer.isHidden = info.offer.isEmpty
        glyph.state = info.state
        glyph.isHidden = info.state == nil
        for button in [menuButton, zoomButton, closeButton] { button.color = H.meta }
        zoomButton.icon = zoomed ? .cornersIn : .cornersOut
        zoomButton.toolTip = zoomed ? T("Restore Pane (⇧⌘↩)", "Restaurar painel (⇧⌘↩)") : T("Maximize Pane (⇧⌘↩)", "Maximizar painel (⇧⌘↩)")
        closeButton.toolTip = T("Close Pane (⌘W)", "Fechar painel (⌘W)")
        // Under the pointer only: the mockups' header has none. They take no room at rest, so the
        // cost sits at the right edge as drawn.
        buttons.isHidden = !hovering
        needsDisplay = true
    }

    /// The pane's line under the header (components.pane.header.borderBottom).
    override func draw(_ dirtyRect: NSRect) {
        H.borderBottom.setFill()
        NSRect(x: 0, y: bounds.height - DesignTokens.Stroke.hairline, width: bounds.width, height: DesignTokens.Stroke.hairline).fill()
    }
}

/// A small icon button of the header: a soft fill under the pointer.
@MainActor
final class PaneHeaderButton: NSView {
    var icon: Icon { didSet { if icon != oldValue { refresh() } } }
    var color: NSColor = .secondaryLabelColor { didSet { refresh() } }
    var onPress: (() -> Void)?
    private let image = NSImageView()
    private var hovering = false { didSet { layer?.backgroundColor = hovering ? NSColor.labelColor.withAlphaComponent(0.1).cgColor : nil } }

    init(icon: Icon) {
        self.icon = icon
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        image.translatesAutoresizingMaskIntoConstraints = false
        addSubview(image)
        let side = UILooks.pt(18)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: side), heightAnchor.constraint(equalToConstant: side),
            image.centerXAnchor.constraint(equalTo: centerXAnchor), image.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PaneHeaderButton is created in code") }

    private func refresh() {
        image.image = icon.fittedImage(size: UILooks.pt(12))
        image.contentTintColor = color
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if alphaValue > 0, bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }
}

/// "Open :5173 in preview" (components.pane.header.offer): a blue chip that runs `onPress`.
@MainActor
final class PaneHeaderOffer: NSView {
    typealias O = DesignTokens.Pane.Header.Offer
    var onPress: (() -> Void)?
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = O.bg.cgColor
        layer?.cornerRadius = UILooks.pt(O.radius)
        label.font = UILooks.font(O.fontSize, weight: O.weight)
        label.textColor = O.color
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(O.padding.left)),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(O.padding.right)),
            label.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(O.padding.top)),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -UILooks.pt(O.padding.bottom)),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PaneHeaderOffer is created in code") }

    var text: String {
        get { label.stringValue }
        set {
            label.textColor = O.color
            label.stringValue = newValue
            setAccessibilityLabel(newValue)
        }
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }
}
