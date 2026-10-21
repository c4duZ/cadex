import AppKit
import Strings
import UILooks

/// "Customize": a card under the customize button, in the theme's colors
/// like the settings window, with every page of the catalog to show, hide
/// and drag into place (docs/spec/sidebar.md). The owner asked on
/// 2026-10-21 for the prototype's look instead of a system popover (blue
/// switches, focus ring, its own material). Each change is saved at once;
/// Esc or a click elsewhere closes it.
@MainActor
final class SidebarCustomizePanel: NSPanel {
    private let catalog: [SidebarItem]
    private var shown: [String]
    /// The whole list as the panel shows it: shown first, then hidden.
    private var order: [String]
    private let colors: SidebarColors
    private let onChange: ([String]) -> Void
    private let list = SidebarCustomizeList()

    init(catalog: [SidebarItem], shown: [String], colors: SidebarColors, onChange: @escaping ([String]) -> Void) {
        self.catalog = catalog
        self.shown = shown
        order = SidebarLayout.customizeOrder(shown: shown, known: catalog.map(\.id))
        self.colors = colors
        self.onChange = onChange
        super.init(contentRect: NSRect(x: 0, y: 0, width: UILooks.pt(340), height: 100),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isReleasedWhenClosed = false
        contentView = makeCard()
        list.onFlip = { [weak self] id in self?.flip(id) }
        list.onMove = { [weak self] id, index in self?.move(id, to: index) }
        refreshList()
    }

    override var canBecomeKey: Bool { true }

    /// Under `anchor`, its right edge lined up with the anchor's, kept on screen.
    func show(below anchor: NSView) {
        guard let parent = anchor.window else { return }
        contentView?.layoutSubtreeIfNeeded()
        let size = contentView?.fittingSize ?? frame.size
        let rect = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        var origin = NSPoint(x: rect.maxX - size.width + UILooks.pt(6), y: rect.minY - UILooks.pt(6) - size.height)
        if let screen = parent.screen?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
            origin.y = max(origin.y, screen.minY + 8)
        }
        setFrame(NSRect(origin: origin, size: size), display: true)
        parent.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)
    }

    override func resignKey() {
        super.resignKey()
        dismiss()
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }

    func dismiss() {
        parent?.removeChildWindow(self)
        orderOut(nil)
    }

    private func makeCard() -> NSView {
        let title = NSTextField(labelWithString: T("Customize", "Personalizar"))
        title.font = UILooks.font(15, weight: .semibold)
        title.textColor = colors.text
        let note = NSTextField(wrappingLabelWithString: T("Drag to reorder. Also in ⌘K: “Customize Sidebar”.",
                                                          "Arraste para reordenar. Também no ⌘K: “Personalizar o painel lateral”."))
        note.font = UILooks.font(12)
        note.textColor = colors.secondary
        let section = NSTextField(labelWithString: T("Sidebar icons", "Ícones do painel lateral").uppercased())
        section.font = UILooks.font(11, weight: .semibold)
        section.textColor = colors.secondary
        let stack = NSStackView(views: [title, note, section, list])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(14, after: note)
        stack.setCustomSpacing(8, after: section)
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let width = UILooks.pt(340) - 36
        for view in [note, list] as [NSView] { view.widthAnchor.constraint(equalToConstant: width).isActive = true }
        note.preferredMaxLayoutWidth = width
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 1
        card.layer?.borderColor = colors.border.cgColor
        card.layer?.backgroundColor = colors.panel.cgColor
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            card.widthAnchor.constraint(equalToConstant: UILooks.pt(340)),
        ])
        return card
    }

    private func refreshList() {
        list.show(order.compactMap { id in catalog.first { $0.id == id } }, shown: shown, colors: colors)
    }

    private func flip(_ id: String) {
        let ids = SidebarLayout.toggled(shown, id)
        apply(order.filter(ids.contains))
    }

    private func move(_ id: String, to index: Int) {
        order = SidebarLayout.moved(order, id, to: index)
        apply(order.filter(shown.contains))
    }

    private func apply(_ ids: [String]) {
        shown = ids
        onChange(ids)
    }
}
