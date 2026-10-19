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
        // VS Code's tree: 22 pt rows, 8 pt per level (docs/spec/explorer.md).
        rowHeight = 22
        indentationPerLevel = 8
        backgroundColor = .clear
        style = .plain
        allowsMultipleSelection = true
        focusRingType = .none
        dataSource = controller
        delegate = controller
        target = self
        // One click opens, as in VS Code: two clicks for every file was the
        // owner's complaint (2026-10-19).
        action = #selector(rowClicked)
        registerForDraggedTypes([.fileURL])
        setDraggingSourceOperationMask([.move], forLocal: true)
        setDraggingSourceOperationMask([.copy], forLocal: false)
        menu = NSMenu()
        menu?.delegate = self
    }

    private func run(_ id: String) {
        _ = controller?.run(id)
    }

    // MARK: Pointer (hover and indent guides)

    /// The row under the pointer, drawn with a light fill.
    private(set) var hoveredRow = -1
    /// Indent guides show while the pointer is over the tree, as in VS Code.
    private(set) var pointerInside = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        pointerInside = true
        redrawRows()
    }

    override func mouseExited(with event: NSEvent) {
        pointerInside = false
        setHovered(-1)
        redrawRows()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        setHovered(row(at: convert(event.locationInWindow, from: nil)))
    }

    private func setHovered(_ row: Int) {
        guard row != hoveredRow else { return }
        let old = hoveredRow
        hoveredRow = row
        for r in [old, row] where r >= 0 && r < numberOfRows { rowView(atRow: r, makeIfNecessary: false)?.needsDisplay = true }
    }

    private func redrawRows() {
        enumerateAvailableRowViews { view, _ in view.needsDisplay = true }
    }

    /// Where the guides of a row go: under the arrow of each folder above
    /// it, read from the outline itself. A fixed distance guessed from the
    /// cell put them across the arrows (owner's screenshot, 2026-10-19).
    func guideXs(row: Int) -> [CGFloat] {
        var xs: [CGFloat] = []
        var item = self.item(atRow: row)
        while let parent = self.parent(forItem: item) {
            let parentRow = self.row(forItem: parent)
            guard parentRow >= 0 else { break }
            xs.append(frameOfOutlineCell(atRow: parentRow).midX)
            item = parent
        }
        return xs
    }

    /// A file opens in its tab, a folder opens or closes. Not with ⌘ or ⇧
    /// (they build a selection), and not on the arrow, which already did it.
    @objc private func rowClicked() {
        guard clickedRow >= 0, let event = NSApp.currentEvent else { return }
        if !event.modifierFlags.intersection([.command, .shift]).isEmpty { return }
        let point = convert(event.locationInWindow, from: nil)
        if frameOfOutlineCell(atRow: clickedRow).insetBy(dx: -4, dy: 0).contains(point) { return }
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
