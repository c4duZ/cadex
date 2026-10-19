import AppKit

/// The tree's NSOutlineView. Keys that only make sense in the tree (Enter
/// opens, F2 renames, ⌘⌫ trashes, ⌘C and ⌘V copy files) are handled here,
/// not as app-wide shortcuts, because the terminal needs the same keys
/// (⌘⌫ deletes the line, F2 goes to programs like htop). They still only
/// run commands by id (ADR 0005).
@MainActor
final class ExplorerOutline: NSOutlineView {
    private weak var controller: ExplorerController?

    func configure(controller: ExplorerController) {
        self.controller = controller
        let column = NSTableColumn(identifier: .init("name"))
        column.resizingMask = .autoresizingMask
        addTableColumn(column)
        columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outlineTableColumn = column
        headerView = nil
        rowHeight = 22
        indentationPerLevel = 12
        backgroundColor = .clear
        style = .plain
        allowsMultipleSelection = true
        focusRingType = .none
        dataSource = controller
        delegate = controller
        target = self
        doubleAction = #selector(openClicked)
        registerForDraggedTypes([.fileURL])
        setDraggingSourceOperationMask([.move], forLocal: true)
        setDraggingSourceOperationMask([.copy], forLocal: false)
        menu = NSMenu()
        menu?.delegate = self
    }

    private func run(_ id: String) {
        _ = controller?.run(id)
    }

    @objc private func openClicked() {
        guard clickedRow >= 0 else { return }
        run("explorer.open")
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (event.keyCode, flags) {
        case (36, []), (76, []): run("explorer.open")       // Return, keypad Enter
        case (120, []): run("explorer.rename")               // F2
        case (51, [.command]): run("explorer.trash")         // ⌘⌫
        default: super.keyDown(with: event)
        }
    }

    @objc func copy(_ sender: Any?) { run("explorer.copy-files") }
    @objc func paste(_ sender: Any?) { run("explorer.paste-files") }

    /// Right-clicking a row outside the selection selects it first, as in
    /// the Finder.
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, !selectedRowIndexes.contains(row) {
            selectRowIndexes([row], byExtendingSelection: false)
        }
        return super.menu(for: event)
    }
}

extension ExplorerOutline: NSMenuDelegate {
    /// The context menu, rebuilt each time from the commands so availability
    /// is current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let controller else { return }
        for id in ExplorerCommands.contextMenu {
            guard let id else {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: ExplorerCommands.title(id), action: #selector(runMenuItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.isEnabled = controller.unavailableReason(id) == nil
            menu.addItem(item)
        }
        menu.autoenablesItems = false
    }

    @objc private func runMenuItem(_ item: NSMenuItem) {
        if let id = item.representedObject as? String { run(id) }
    }
}
