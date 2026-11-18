import AppKit
import Editor
import Menus
import Strings
import UILooks

/// The review's file list on the left (docs/spec/review.md): each changed
/// file as the Changes tab's row (its letter, name, folder, +/−; plan 31 A);
/// a click goes to the file in the stack, and the list follows the cursor.
/// A right click offers to open the file.
@MainActor
final class ReviewTree: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let table = MenuTableView()
    let scroll = NSScrollView()
    private(set) var files: [GitRepository.ReviewFile] = []
    var onPick: ((Int) -> Void)?
    var onOpenFile: ((Int) -> Void)?
    var onResolve: ((Int) -> Void)?
    private var following = false

    override init() {
        super.init()
        let column = NSTableColumn(identifier: .init("file"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = UILooks.pt(DesignTokens.Inspector.FileRow.height)
        // Plain and clear: the source-list style painted a grey slab over
        // the theme's panel (seen in the app, 2026-11-15).
        table.backgroundColor = .clear
        table.style = .plain
        // The frame's selected row (bg.selected), drawn by ReviewTreeRow, not the system's blue.
        table.selectionHighlightStyle = .regular
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.dataSource = self
        table.delegate = self
        table.contextEntries = { [weak self] row in
            guard let self, files.indices.contains(row) else { return [] }
            var entries = [MenuEntry(T("Open File", "Abrir o arquivo"), icon: .file) { [weak self] in self?.onOpenFile?(row) }]
            if files[row].status == "U" {
                entries.insert(MenuEntry(T("Resolve Conflict", "Resolver o conflito"), icon: .gitDiff) { [weak self] in self?.onResolve?(row) }, at: 0)
            }
            return entries
        }
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
    }

    func show(_ files: [GitRepository.ReviewFile]) {
        self.files = files
        table.reloadData()
        paintChosen()
    }

    /// The cursor is in this file now: select it without jumping back.
    func follow(_ index: Int) {
        guard files.indices.contains(index), table.selectedRow != index else { return }
        following = true
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        table.scrollRowToVisible(index)
        paintChosen()
        following = false
    }

    func numberOfRows(in tableView: NSTableView) -> Int { files.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
        paintChosen()
        guard !following, files.indices.contains(table.selectedRow) else { return }
        onPick?(table.selectedRow)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let file = files[row]
        let view = ChangesRowView(ChangesRow(file: file, entry: nil))
        view.toolTip = file.orig.isEmpty ? file.path : "\(file.orig) → \(file.path)"
        return view
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ReviewTreeRow()
    }

    // Marked as each row comes on: rows made by a reload were born before the selection came back.
    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        (rowView as? ReviewTreeRow)?.chosen = row == tableView.selectedRow
    }

    /// Each row on screen shows whether it is the selected one.
    private func paintChosen() {
        table.enumerateAvailableRowViews { view, row in (view as? ReviewTreeRow)?.chosen = row == self.table.selectedRow }
    }
}

/// The selected file in the right panel's chosen box (components.inspector.tree.selected), set by
/// the list: the table's own selection drawing did not show (2026-11-17), as in the history's list.
final class ReviewTreeRow: NSTableRowView {
    var chosen = false { didSet { if chosen != oldValue { needsDisplay = true } } }

    override func drawBackground(in dirtyRect: NSRect) {
        guard chosen else { return }
        typealias Selected = DesignTokens.Inspector.Tree.Selected
        let radius = UILooks.pt(DesignTokens.Inspector.Commit.radius)
        Selected.bg.setFill()
        // In from the list's edges by the row's own padding, as the Changes rows sit.
        let inset = UILooks.pt(DesignTokens.Inspector.FileRow.padding.left) / 2
        NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: 0), xRadius: radius, yRadius: radius).fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {}
}
