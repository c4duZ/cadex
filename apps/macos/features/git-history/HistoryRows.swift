import AppKit
import UILooks
import Icons
import Menus
import Strings

/// The commits' table: graph, subject with the refs, author, date and sha.
/// Cells are made only for the rows on screen and reused; nearing the end
/// asks for the next page.
@MainActor
final class HistoryRows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    weak var document: HistoryDocument?
    weak var table: MenuTableView?
    var commits: [HistoryCommit] = []
    var showsGraph = true
    /// Selecting a row from code (after a reload) does not reload details.
    var selecting = false
    /// The next page is asked this many rows before the end.
    static let prefetch = 100

    private static let dates: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: Strings.language == .pt ? "pt_BR" : "en_US")
        f.unitsStyle = .full
        return f
    }()

    /// The full date, in the interface language like the relative one (the system's
    /// language may differ: the details read "17 October" on 2026-10-19).
    static let fullDates: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: Strings.language == .pt ? "pt_BR" : "en_US")
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    func build() {
        guard let table else { return }
        for (id, title, width) in [("graph", "", 60.0), ("subject", T("Description", "Descrição"), 420), ("author", T("Author", "Autor"), 140), ("date", T("Date", "Data"), 120), ("sha", "Commit", 70)] {
            let column = NSTableColumn(identifier: .init(id))
            column.title = title
            column.width = width
            column.minWidth = id == "graph" ? 20 : 50
            column.resizingMask = id == "subject" ? [.autoresizingMask, .userResizingMask] : .userResizingMask
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.rowHeight = UILooks.rowHeight(22)
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.style = .plain
        table.usesAlternatingRowBackgroundColors = false
        table.dataSource = self
        table.delegate = self
        table.contextEntries = { [weak self] row in self?.menuEntries(row) ?? [] }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { commits.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        // A local filter only looks at what is loaded; the full list and a
        // repository search grow. After this pass: loading changes the rows
        // the table is drawing.
        let filtering = document?.searchResults == nil && document?.filter.isEmpty == false
        if row >= commits.count - Self.prefetch, !filtering {
            DispatchQueue.main.async { [weak self] in self?.document?.loadMore() }
        }
        let commit = commits[row]
        let id = tableColumn?.identifier.rawValue ?? ""
        if id == "graph" {
            let view = tableView.makeView(withIdentifier: .init("graph"), owner: nil) as? HistoryGraphView ?? HistoryGraphView()
            view.identifier = .init("graph")
            view.graph = showsGraph ? commit.graph : nil
            view.isMerge = commit.parents.count > 1
            view.isHead = commit.refs.contains { $0 == "HEAD" || $0.hasPrefix("HEAD -> ") }
            return view
        }
        let cell = tableView.makeView(withIdentifier: .init(id), owner: nil) as? NSTableCellView ?? Self.textCell(id)
        switch id {
        case "subject": cell.textField?.attributedStringValue = Self.subject(commit)
        case "author": cell.textField?.stringValue = commit.author
        case "date": cell.textField?.stringValue = Self.dates.localizedString(for: commit.date, relativeTo: Date())
        default: cell.textField?.stringValue = commit.shortSha
        }
        cell.toolTip = id == "date" ? Self.fullDates.string(from: commit.date) : nil
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !selecting, let table else { return }
        let row = table.selectedRow
        document?.select(row >= 0 && row < commits.count ? commits[row] : nil)
    }

    private static func textCell(_ id: String) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = .init(id)
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.font = id == "sha" ? UILooks.monospaced(11) : UILooks.font(12)
        if id != "subject" { label.textColor = .secondaryLabelColor }
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    /// The refs as tinted labels before the subject: branches blue, the
    /// current one bold, remotes grey, tags yellow.
    static func subject(_ commit: HistoryCommit) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for ref in commit.refs where ref != "HEAD" {
            let current = ref.hasPrefix("HEAD -> ")
            let name = current ? String(ref.dropFirst(8)) : ref.hasPrefix("tag: ") ? String(ref.dropFirst(5)) : ref
            let color: NSColor = ref.hasPrefix("tag: ") ? .systemYellow : name.contains("/") ? .systemGray : .systemBlue
            text.append(NSAttributedString(string: " \(name) ", attributes: [
                .font: UILooks.font(11, weight: current ? .bold : .medium),
                .foregroundColor: color,
                .backgroundColor: color.withAlphaComponent(0.15),
            ]))
            text.append(NSAttributedString(string: " "))
        }
        text.append(NSAttributedString(string: commit.subject, attributes: [.font: UILooks.font(12)]))
        return text
    }

    /// Each item runs a registered command on the clicked commit, which
    /// becomes the selection first so the command acts on it.
    private func menuEntries(_ row: Int) -> [MenuEntry] {
        guard row >= 0 else { return [] }
        let items: [(String, String, Icon)] = [(T("Copy SHA", "Copiar sha"), "history.copy-sha", .copy), (T("Open on Remote", "Abrir no remoto"), "history.open-remote", .arrowSquareOut)]
        return items.map { title, id, icon in
            MenuEntry(title, icon: icon) { [weak self] in
                if let table = self?.table, row != table.selectedRow {
                    table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }
                _ = self?.document?.runCommand?(id)
            }
        }
    }
}
