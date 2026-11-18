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

/// The table: one cell per conversation (title over the detail, as a row of
/// the project page's list; plan 31 C), a group's label per group; only the
/// rows on screen are drawn. Double click resumes; the right click lists
/// what to do with it.
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
        intercellSpacing = NSSize(width: 0, height: UILooks.pt(DesignTokens.Project.Columns.listGap))
        // The row's own card shows it; no system blue.
        selectionHighlightStyle = .none
        dataSource = self
        delegate = self
        target = self
        doubleAction = #selector(resumeClicked)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    // No system group rows: a group's label sits on the page, it does not float over the list.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .header = items[row] { return false }
        return true
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        typealias R = DesignTokens.Project.Row
        if case .header = items[row] { return UILooks.pt(DesignTokens.Project.Label.fontSize + R.padding.top + R.padding.bottom) }
        return UILooks.pt(R.padding.top + R.padding.bottom + DesignTokens.FontSize.body + R.Meta.fontSize + R.textGap) + UILooks.labelInset * 4
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        typealias R = DesignTokens.Project.Row
        switch items[row] {
        case .header(let title, let count):
            let label = FrameField.label("\(title)  \(count)")
            let cell = NSView()
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor), label.bottomAnchor.constraint(equalTo: cell.bottomAnchor)])
            return cell
        case .entry(let entry):
            let title = FrameField.text(entry.title, color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.semibold)
            let detail = FrameField.text(AgentHistoryRows.detail(entry, accountName: accountName(entry.account)), size: R.Meta.fontSize, color: R.Meta.color)
            let words = FrameField.column([title, detail], gap: R.textGap)
            let card = FrameBox()
            card.box(bg: R.bg, border: R.border, radius: R.radius)
            card.hold(words, padding: R.padding)
            card.toolTip = entry.title + "\n" + (entry.cwd as NSString).abbreviatingWithTildeInPath
                + T("\nDouble click: resume in its account", "\nDuplo clique: retomar na conta dela")
            return card
        }
    }

    func entry(at row: Int) -> AgentHistoryEntry? {
        guard row >= 0, row < items.count, case .entry(let entry) = items[row] else { return nil }
        return entry
    }

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
