import AppKit
import Strings
import UILooks

/// "Customize": a window of its own in front of the app, like the settings
/// window, with every page of the catalog to show, hide and drag into place
/// (docs/spec/sidebar.md). The owner asked on 2026-10-21 for the
/// prototype's look: first a system popover (blue switches, focus ring),
/// then a card under the button, both refused. Each change is saved at
/// once; Esc, ⌘W or the close button closes it.
@MainActor
final class SidebarCustomizePanel: NSWindow {
    private let catalog: [SidebarItem]
    private var shown: [String]
    /// The whole list as the window shows it: shown first, then hidden.
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
        super.init(contentRect: NSRect(x: 0, y: 0, width: UILooks.pt(420), height: 300),
                   styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        title = T("Customize", "Personalizar")
        isReleasedWhenClosed = false
        // Over the app in full screen, in the same Space, as the settings window.
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        backgroundColor = colors.panel
        contentView = makeContent()
        list.onFlip = { [weak self] id in self?.flip(id) }
        list.onMove = { [weak self] id, index in self?.move(id, to: index) }
        refreshList()
    }

    /// Centered over the window it was opened from, with its look.
    func show(over parent: NSWindow?) {
        appearance = parent?.effectiveAppearance
        contentView?.layoutSubtreeIfNeeded()
        if let size = contentView?.fittingSize { setContentSize(size) }
        if let parent {
            let frame = parent.frame
            setFrameOrigin(NSPoint(x: frame.midX - self.frame.width / 2, y: frame.midY - self.frame.height / 2))
        } else {
            center()
        }
        makeKeyAndOrderFront(nil)
    }

    override func cancelOperation(_ sender: Any?) { close() }

    private func makeContent() -> NSView {
        let heading = NSTextField(labelWithString: T("Customize", "Personalizar"))
        heading.font = UILooks.font(15, weight: .semibold)
        heading.textColor = colors.text
        let note = NSTextField(wrappingLabelWithString: T("Drag to reorder. Also in ⌘K: “Customize Sidebar”.",
                                                          "Arraste para reordenar. Também no ⌘K: “Personalizar o painel lateral”."))
        note.font = UILooks.font(12)
        note.textColor = colors.secondary
        let section = NSTextField(labelWithString: T("Sidebar icons", "Ícones do painel lateral").uppercased())
        section.font = UILooks.font(11, weight: .semibold)
        section.textColor = colors.secondary
        let stack = NSStackView(views: [heading, note, section, list])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(16, after: note)
        stack.setCustomSpacing(8, after: section)
        // The top leaves room for the close button in the transparent title bar.
        stack.edgeInsets = NSEdgeInsets(top: 40, left: 22, bottom: 22, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let width = UILooks.pt(420) - 44
        for view in [note, list] as [NSView] { view.widthAnchor.constraint(equalToConstant: width).isActive = true }
        note.preferredMaxLayoutWidth = width
        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            root.widthAnchor.constraint(equalToConstant: UILooks.pt(420)),
        ])
        return root
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
