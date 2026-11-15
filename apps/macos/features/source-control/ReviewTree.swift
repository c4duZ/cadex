import AppKit
import Editor
import Menus
import Strings
import UILooks

/// The review's file list on the left (docs/spec/review.md): each changed
/// file with its letter, its name and its folder, and +/−; a click goes to
/// the file in the stack, and the list follows the cursor. A right click
/// offers to open the file.
@MainActor
final class ReviewTree: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let table = MenuTableView()
    let scroll = NSScrollView()
    private(set) var files: [GitRepository.ReviewFile] = []
    var onPick: ((Int) -> Void)?
    var onOpenFile: ((Int) -> Void)?
    private var following = false

    override init() {
        super.init()
        let column = NSTableColumn(identifier: .init("file"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = UILooks.rowHeight(36)
        // Plain and clear: the source-list style painted a grey slab over
        // the theme's panel (seen in the app, 2026-11-15).
        table.backgroundColor = .clear
        table.style = .plain
        table.selectionHighlightStyle = .regular
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.dataSource = self
        table.delegate = self
        table.contextEntries = { [weak self] row in
            guard let self, files.indices.contains(row) else { return [] }
            return [MenuEntry(T("Open File", "Abrir o arquivo"), icon: .file) { [weak self] in self?.onOpenFile?(row) }]
        }
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
    }

    func show(_ files: [GitRepository.ReviewFile]) {
        self.files = files
        table.reloadData()
    }

    /// The cursor is in this file now: select it without jumping back.
    func follow(_ index: Int) {
        guard files.indices.contains(index), table.selectedRow != index else { return }
        following = true
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        table.scrollRowToVisible(index)
        following = false
    }

    func numberOfRows(in tableView: NSTableView) -> Int { files.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !following, files.indices.contains(table.selectedRow) else { return }
        onPick?(table.selectedRow)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let file = files[row]
        let letter = text(String(file.status), size: 11, weight: .bold, color: ReviewTextView.statusColor(file.status))
        letter.setContentHuggingPriority(.required, for: .horizontal)
        let name = text((file.path as NSString).lastPathComponent, size: 12, weight: .medium, color: .labelColor)
        let folder = text((file.path as NSString).deletingLastPathComponent, size: 10.5, color: .secondaryLabelColor)
        let counts = text(file.added.map { "+\($0) −\(file.removed ?? 0)" } ?? "bin", size: 10.5, color: .secondaryLabelColor)
        counts.setContentHuggingPriority(.required, for: .horizontal)
        counts.setContentCompressionResistancePriority(.required, for: .horizontal)
        let names = NSStackView(views: [name, folder])
        names.orientation = .vertical
        names.alignment = .leading
        names.spacing = 0
        let line = NSStackView(views: [letter, names, NSView(), counts])
        line.spacing = 7
        line.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 8)
        line.toolTip = file.orig.isEmpty ? file.path : "\(file.orig) → \(file.path)"
        return line
    }

    private func text(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        field.font = UILooks.font(size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingMiddle
        return field
    }
}
