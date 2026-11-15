import AppKit
import Menus
import Strings
import UILooks

/// How the History groups its conversations (docs/spec/agents.md, Histórico).
public enum AgentHistoryGrouping: String, CaseIterable, Sendable {
    case project, folder, account
}

/// What the list shows: a group's title with its count, or a conversation.
enum AgentHistoryItem: Equatable {
    case header(String, Int)
    case entry(AgentHistoryEntry)
}

/// The list's rows from the entries: filtered by the scope (this project or
/// all) and the search (the words in the title, folder or branch, or in what
/// was said: `matches`, from the text index), then grouped, the newest group
/// first. Pure, so it is tested without a window.
enum AgentHistoryRows {
    static func make(_ entries: [AgentHistoryEntry], query: String, matches: Set<String>?, project: String?,
                     grouping: AgentHistoryGrouping, accountName: (String) -> String,
                     projectOf: (String) -> String = { AgentProject.of($0).root }) -> [AgentHistoryItem] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        let shown = entries.filter { entry in
            if let project, projectOf(entry.cwd) != project { return false }
            guard !words.isEmpty else { return true }
            let plain = [entry.title, entry.cwd, entry.branch].joined(separator: " ").lowercased()
            return words.allSatisfy(plain.contains) || matches?.contains(entry.path) == true
        }
        var order: [String] = []
        var groups: [String: [AgentHistoryEntry]] = [:]
        for entry in shown {
            let key = switch grouping {
            case .project: (projectOf(entry.cwd) as NSString).lastPathComponent
            case .folder: (entry.cwd as NSString).abbreviatingWithTildeInPath
            case .account: accountName(entry.account)
            }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(entry)
        }
        return order.flatMap { key in [AgentHistoryItem.header(key.isEmpty ? "—" : key, groups[key]!.count)] + groups[key]!.map { .entry($0) } }
    }

    /// "cadex · main · bhband · 3h": where, which branch, whose, when.
    static func detail(_ entry: AgentHistoryEntry, accountName: String, now: Date = Date()) -> String {
        [(entry.cwd as NSString).lastPathComponent, entry.branch, accountName, entry.updated.map { AgentTime.short(since: $0, now: now) } ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// The table: one cell per conversation (title over the detail), a group
/// row per group; only the rows on screen are drawn. Double click resumes;
/// the right click lists what to do with it.
@MainActor
final class AgentHistoryTable: NSTableView, NSTableViewDataSource, NSTableViewDelegate {
    var items: [AgentHistoryItem] = [] { didSet { reloadData() } }
    var colors = AgentColors() { didSet { reloadData() } }
    var accountName: (String) -> String = { ($0 as NSString).lastPathComponent }
    var onResume: ((AgentHistoryEntry) -> Void)?
    var menuFor: ((AgentHistoryEntry) -> [MenuEntry])?

    init() {
        super.init(frame: .zero)
        let column = NSTableColumn(identifier: .init("main"))
        addTableColumn(column)
        headerView = nil
        backgroundColor = .clear
        style = .plain
        intercellSpacing = NSSize(width: 0, height: 2)
        selectionHighlightStyle = .regular
        dataSource = self
        delegate = self
        target = self
        doubleAction = #selector(resumeClicked)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = items[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { !self.tableView(tableView, isGroupRow: row) }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .header = items[row] { return UILooks.pt(24) }
        return UILooks.pt(38)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch items[row] {
        case .header(let title, let count):
            let label = AgentText.label("\(title)  \(count)", size: 11, weight: .semibold, color: colors.secondary)
            return wrap(label, top: 6)
        case .entry(let entry):
            let title = AgentText.label(entry.title, size: 12, color: colors.text)
            let detail = AgentText.label(AgentHistoryRows.detail(entry, accountName: accountName(entry.account)), size: 11, color: colors.secondary)
            let stack = NSStackView(views: [title, detail])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 1
            let cell = wrap(stack, top: 3)
            cell.toolTip = entry.title + "\n" + (entry.cwd as NSString).abbreviatingWithTildeInPath
                + T("\nDouble click: resume in its account", "\nDuplo clique: retomar na conta dela")
            return cell
        }
    }

    private func wrap(_ content: NSView, top: CGFloat) -> NSView {
        let cell = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            content.topAnchor.constraint(equalTo: cell.topAnchor, constant: top),
        ])
        return cell
    }

    func entry(at row: Int) -> AgentHistoryEntry? {
        guard row >= 0, row < items.count, case .entry(let entry) = items[row] else { return nil }
        return entry
    }

    var selectedEntry: AgentHistoryEntry? { entry(at: selectedRow) }

    @objc private func resumeClicked() {
        if let entry = entry(at: clickedRow) { onResume?(entry) }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard let entry = entry(at: row), let entries = menuFor?(entry) else { return }
        selectRowIndexes([row], byExtendingSelection: false)
        PopupMenu.show(entries, at: point, in: self)
    }
}
