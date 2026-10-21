import AppKit
import Icons
import Strings
import UILooks

/// "Customize": every page of the catalog with a switch to show it and a
/// handle to drag it into place (docs/spec/sidebar.md). Opened as a popover
/// under the customize button; each change is saved at once.
@MainActor
final class SidebarCustomizePanel: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private static let dragType = NSPasteboard.PasteboardType("dev.cadex.sidebar-item")

    private let catalog: [SidebarItem]
    private var shown: [String]
    /// The whole list as the panel shows it: shown first, then hidden.
    private var order: [String]
    private let onChange: ([String]) -> Void
    private let table = NSTableView()

    init(catalog: [SidebarItem], shown: [String], onChange: @escaping ([String]) -> Void) {
        self.catalog = catalog
        self.shown = shown
        order = SidebarLayout.customizeOrder(shown: shown, known: catalog.map(\.id))
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SidebarCustomizePanel is created in code") }

    override func loadView() {
        let title = NSTextField(labelWithString: T("Sidebar", "Painel lateral"))
        title.font = UILooks.font(13, weight: .semibold)
        let note = NSTextField(labelWithString: T("Drag to reorder. Also in ⌘K: “Customize Sidebar”.",
                                                  "Arraste para reordenar. Também no ⌘K: “Personalizar o painel lateral”."))
        note.font = UILooks.font(11)
        note.textColor = .secondaryLabelColor
        table.addTableColumn(NSTableColumn(identifier: .init("item")))
        table.headerView = nil
        table.rowHeight = UILooks.rowHeight(30)
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.dataSource = self
        table.delegate = self
        table.registerForDraggedTypes([Self.dragType])
        table.draggingDestinationFeedbackStyle = .gap
        let stack = NSStackView(views: [title, note, table])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        table.widthAnchor.constraint(equalToConstant: UILooks.pt(250)).isActive = true
        table.heightAnchor.constraint(equalToConstant: CGFloat(order.count) * (table.rowHeight + 2)).isActive = true
        view = stack
    }

    func numberOfRows(in tableView: NSTableView) -> Int { order.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let item = catalog.first(where: { $0.id == order[row] }) else { return nil }
        let handle = NSImageView(image: Icon.dotsSixVertical.image(size: UILooks.pt(13)))
        handle.contentTintColor = .tertiaryLabelColor
        let icon = NSImageView(image: item.icon.image(size: UILooks.pt(15)))
        icon.contentTintColor = .secondaryLabelColor
        let title = NSTextField(labelWithString: item.title)
        title.font = UILooks.font(13)
        let key = NSTextField(labelWithString: item.shortcut ?? "")
        key.font = UILooks.font(11)
        key.textColor = .secondaryLabelColor
        let toggle = NSSwitch()
        toggle.controlSize = .mini
        toggle.state = shown.contains(item.id) ? .on : .off
        toggle.setAccessibilityLabel(T("Show ", "Mostrar ") + item.title)
        toggle.target = self
        toggle.action = #selector(flip(_:))
        toggle.identifier = .init(item.id)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [handle, icon, title, spacer, key, toggle])
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        return row
    }

    @objc private func flip(_ sender: NSSwitch) {
        guard let id = sender.identifier?.rawValue else { return }
        apply(SidebarLayout.toggled(shown, id).sorted { index($0) < index($1) })
    }

    private func index(_ id: String) -> Int { order.firstIndex(of: id) ?? .max }

    private func apply(_ ids: [String]) {
        shown = ids
        onChange(ids)
    }

    // MARK: Drag to reorder

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(order[row], forType: Self.dragType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        dropOperation == .above ? .move : []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let id = info.draggingPasteboard.pasteboardItems?.first?.string(forType: Self.dragType),
              let from = order.firstIndex(of: id) else { return false }
        order = SidebarLayout.moved(order, id, to: from < row ? row - 1 : row)
        tableView.reloadData()
        apply(order.filter(shown.contains))
        return true
    }
}
