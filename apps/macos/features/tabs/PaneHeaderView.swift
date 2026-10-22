import AppKit
import Icons
import Strings
import UILooks

/// The slim line on top of a pane when its tab has more than one
/// (docs/spec/tabs.md, "Cabeçalho dos painéis"): what the pane shows on the
/// left, and on the right "+" (what opens beside, maximize, close),
/// maximize and close. It fixes issue #1: a
/// file opened beside the terminal had no visible way to close only it.
/// Lighter than the tab strip above it (no fill, a hairline below), so the
/// window does not read as two rows of tabs; the close button always shows
/// on the focused pane, the rest on hover (as iTerm2's per-pane title bar,
/// Zed and VS Code do, research of 2026-10-22).
@MainActor
final class PaneHeaderView: NSView {
    static var height: CGFloat { UILooks.pt(24) }

    struct Info: Equatable {
        var title: String
        var icon: Icon
        var iconColor: NSColor?
        var image: NSImage?
        var dirty = false
    }

    enum DragPhase { case began, moved, ended }
    enum Action { case focus, close, zoom, menu(NSView), drag(DragPhase, NSPoint) }

    var info = Info(title: "", icon: .terminalWindow) { didSet { if info != oldValue { refresh() } } }
    var focused = false { didSet { if focused != oldValue { refresh() } } }
    var zoomed = false { didSet { if zoomed != oldValue { refresh() } } }
    var style = TabBarView.Style(activeFill: .controlBackgroundColor, hoverFill: .quaternaryLabelColor,
                                 text: .labelColor, secondaryText: .secondaryLabelColor) { didSet { refresh() } }
    var onAction: ((Action) -> Void)?

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let menuButton = PaneHeaderButton(icon: .plus)
    private let zoomButton = PaneHeaderButton(icon: .cornersOut)
    private let closeButton = PaneHeaderButton(icon: .x)
    private var hovering = false { didSet { if hovering != oldValue { refresh() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = UILooks.font(11.5)
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        menuButton.onPress = { [weak self] in self.map { $0.onAction?(.menu($0.menuButton)) } }
        zoomButton.onPress = { [weak self] in self?.onAction?(.zoom) }
        closeButton.onPress = { [weak self] in self?.onAction?(.close) }
        menuButton.toolTip = T("Open Beside, Split, Maximize, Close", "Abrir ao lado, dividir, maximizar, fechar")
        let buttons = NSStackView(views: [menuButton, zoomButton, closeButton])
        buttons.spacing = 2
        let row = NSStackView(views: [iconView, label, NSView(), buttons])
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: UILooks.pt(13)),
            iconView.heightAnchor.constraint(equalToConstant: UILooks.pt(13)),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(10)),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(4)),
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
        label.textColor = focused ? style.text : style.secondaryText
        if let image = info.image {
            iconView.image = image
            iconView.contentTintColor = nil
        } else {
            iconView.image = info.icon.image(size: UILooks.pt(13))
            iconView.contentTintColor = info.iconColor ?? (focused ? style.text : style.secondaryText)
        }
        iconView.alphaValue = focused ? 1 : 0.7
        for button in [menuButton, zoomButton, closeButton] { button.color = focused ? style.text : style.secondaryText }
        zoomButton.icon = zoomed ? .cornersIn : .cornersOut
        zoomButton.toolTip = zoomed ? T("Restore Pane (⇧⌘↩)", "Restaurar painel (⇧⌘↩)") : T("Maximize Pane (⇧⌘↩)", "Maximizar painel (⇧⌘↩)")
        closeButton.toolTip = T("Close Pane (⌘W)", "Fechar painel (⌘W)")
        // The three show together, on the focused pane and under the
        // pointer, and keep their room when they fade: maximize showing
        // apart from the others moved the header (the owner, 2026-10-22).
        let shown = hovering || focused || zoomed
        for button in [menuButton, zoomButton, closeButton] { button.alphaValue = shown ? 1 : 0 }
        needsDisplay = true
    }

    /// The card's ground and a hairline below.
    override func draw(_ dirtyRect: NSRect) {
        PaneLooks.cardColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        // The focus is the card's accent outline (PaneLayoutView), along
        // the rounded corners; a line here across the top looked cut.
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
