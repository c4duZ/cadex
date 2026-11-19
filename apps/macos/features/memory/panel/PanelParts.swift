import AppKit
import Icons
import Menus
import Strings
import UILooks

/// The small pieces of the Memória page (components.memoryPanel), shared by its screens.
typealias MP = DesignTokens.MemoryPanel

/// A view that takes a click (and a right click, with a menu): the page's cards, numbers, links and
/// selectors. It runs nothing itself: the caller gives what a click does (a command, ADR 0005).
@MainActor
class PanelPress: FrameBox {
    var onPress: (() -> Void)?
    var entriesFor: (() -> [MenuEntry])?
    /// The pointer over it: the caller paints what hovering shows.
    var onHover: ((Bool) -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { if onPress != nil { addCursorRect(bounds, cursor: .pointingHand) } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }
    override func rightMouseDown(with event: NSEvent) {
        guard let entries = entriesFor?(), !entries.isEmpty else { return super.rightMouseDown(with: event) }
        PopupMenu.show(entries, at: convert(event.locationInWindow, from: nil), in: self)
    }
    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return onPress != nil
    }
}

@MainActor
enum PanelText {
    /// One line in the interface's font.
    static func line(_ text: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = UILooks.font(size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    /// A row of views, centered on the line.
    static func row(_ views: [NSView], gap: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = UILooks.pt(gap)
        return stack
    }

    static func column(_ views: [NSView], gap: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = UILooks.pt(gap)
        return stack
    }

    /// A gap that takes what the row leaves.
    static func spring() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        view.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return view
    }

    /// The count chip ("5", "2 caixa de entrada"): components.memoryPanel.chip, neutral or amber.
    static func chip(_ text: String, amber: Bool = false) -> NSView {
        let box = FrameBox()
        box.box(bg: amber ? MP.Chip.Amber.bg : MP.Chip.Neutral.bg, border: nil, radius: MP.Chip.radius)
        let label = line(text, size: MP.Chip.fontSize, color: amber ? MP.Chip.Amber.color : MP.Chip.Neutral.color, weight: MP.Chip.weight)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        box.hold(label, padding: MP.Chip.padding)
        return box
    }
}

/// A link in the page's blue ("Agentes ↗", "Abrir no Cadex"): components.memoryPanel.link.
@MainActor
final class PanelLink: PanelPress {
    let label: NSTextField

    init(_ title: String, size: CGFloat, action: @escaping () -> Void) {
        label = PanelText.line(title, size: size, color: MP.Link.color, weight: MP.Link.weight)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        super.init(frame: .zero)
        hold(label, padding: NSEdgeInsets())
        onPress = action
        setAccessibilityElement(true)
        setAccessibilityRole(.link)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelLink is created in code") }
}

/// The ⓘ beside a line (screens-memory.md, the access rules): the macOS help button's role, a click
/// opens a popover with the whole sentence, which is also the element's accessibilityHelp, so it is
/// never a tooltip only.
@MainActor
final class PanelHelpButton: PanelPress {
    let text: String
    private let panel = AnchoredPanel()

    init(_ text: String) {
        self.text = text
        super.init(frame: .zero)
        let glyph = NSImageView(image: Icon.info.image(size: UILooks.pt(MP.Nav.Row.icon)))
        glyph.contentTintColor = MP.Help.glyph
        hold(glyph, padding: NSEdgeInsets())
        onPress = { [weak self] in self?.toggle() }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(T("More about this", "Mais sobre isto"))
        setAccessibilityHelp(text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelHelpButton is created in code") }

    private func toggle() {
        if panel.isOpen { return panel.close() }
        let words = NSTextField(wrappingLabelWithString: text)
        words.font = UILooks.font(DesignTokens.FontSize.meta)
        words.textColor = DesignTokens.Color.textBody
        let box = FrameBox()
        box.hold(words, padding: MP.Help.Popover.padding)
        panel.show(box, below: self, width: UILooks.pt(MP.Aside.width) + UILooks.pt(MP.Help.Popover.padding.left) * 2)
    }

    /// For tests: the popover is up.
    var isShowing: Bool { panel.isOpen }
    func press() { onPress?() }
}

/// A selector of the page ("Todos os projetos ▾", "Ordenar: Padrão ▾"): components.memoryPanel.popup;
/// the click lists the choices in the app's menu, the chosen one checked.
@MainActor
final class PanelPopup: PanelPress {
    private let value: NSTextField
    private let prefix: String?

    init(prefix: String?, value text: String) {
        self.prefix = prefix
        value = PanelText.line(text, size: MP.Popup.fontSize, color: DesignTokens.Color.textPrimary)
        super.init(frame: .zero)
        box(bg: MP.Popup.bg, border: MP.Popup.border, radius: MP.Popup.radius)
        var views: [NSView] = []
        if let prefix { views.append(PanelText.line(prefix, size: MP.Popup.fontSize, color: MP.Stat.Label.color)) }
        views.append(value)
        views.append(PanelText.line("▾", size: MP.Popup.Caret.fontSize, color: MP.Popup.Caret.color))
        value.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = PanelText.row(views, gap: MP.Popup.gap)
        hold(row, padding: MP.Popup.padding)
        heightAnchor.constraint(equalToConstant: UILooks.rowHeight(MP.Popup.height)).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.popUpButton)
        say(text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelPopup is created in code") }

    func say(_ text: String) {
        value.stringValue = text
        setAccessibilityLabel((prefix.map { $0 + " " } ?? "") + text)
    }

    var said: String { value.stringValue }

    /// The choices under it; `pick` gets the index chosen.
    func offer(_ titles: [String], chosen: Int, pick: @escaping (Int) -> Void) {
        onPress = { [weak self] in
            guard let self else { return }
            let entries = titles.enumerated().map { index, title in
                MenuEntry(title, icon: index == chosen ? .check : nil) { pick(index) }
            }
            PopupMenu.show(entries, at: NSPoint(x: 0, y: self.bounds.height), in: self)
        }
    }
}
