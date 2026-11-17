import AppKit
import Icons
import Menus
import Strings
import UILooks

/// The history in the sidebar (docs/spec/git-history.md, Na barra lateral):
/// each commit on two lines, the graph and the subject over the author,
/// the time and the short SHA; a click opens the commit's files under it,
/// the graph running on behind them, and a click on a file opens its diff.
/// No details pane: in 240 points it showed nothing (2026-10-21). The way
/// VS Code's and GitLens' sidebar graphs work, from their docs.
@MainActor
final class HistoryCompactRows: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    enum Item: Equatable {
        case commit(Int)
        /// A file of the open commit: the commit's index and the file's.
        case file(Int, Int)
    }

    weak var document: HistoryDocument?
    weak var table: MenuTableView?
    var commits: [HistoryCommit] = []
    var showsGraph = true
    /// The commit whose files show, and those files once they arrive.
    private(set) var expanded: String?
    private(set) var files: [CommitDetails.File] = []
    private(set) var items: [Item] = []

    typealias C = DesignTokens.Inspector.Commit
    /// The drawing's two lines in its padding (components.inspector.commit). Worked out once: the
    /// table asks it for every row on every reload (review of 2026-11-17); the zoom is set at launch.
    static let commitHeight: CGFloat = {
        let lines = NSLayoutManager().defaultLineHeight(for: UILooks.font(C.Title.fontSize))
            + NSLayoutManager().defaultLineHeight(for: UILooks.font(C.Meta.fontSize))
        return UILooks.rowHeight(C.padding.top + C.lineGap + C.padding.bottom) + ceil(lines)
    }()
    /// A file's 24 pt and the 2 pt to the next; the last one the commit's bottom padding instead,
    /// so the box closes under it as the drawing's (2026-11-17).
    static func fileHeight(last: Bool) -> CGFloat {
        UILooks.rowHeight(C.File.height + (last ? C.padding.bottom : C.File.gap))
    }

    /// The rows: every commit, and the open one's files right after it.
    static func items(commits: Int, expandedAt: Int?, files: Int) -> [Item] {
        var items: [Item] = []
        items.reserveCapacity(commits + files)
        for index in 0..<commits {
            items.append(.commit(index))
            if index == expandedAt { items += (0..<files).map { .file(index, $0) } }
        }
        return items
    }

    /// The commits changed (a page, a filter): rebuild the rows.
    func reload() {
        let at = expanded.flatMap { sha in commits.firstIndex { $0.sha == sha } }
        if at == nil { expanded = nil; files = [] }
        items = Self.items(commits: commits.count, expandedAt: at, files: files.count)
        table?.reloadData()
    }

    /// The selected commit's details came: its files go under it.
    func detailsArrived() {
        guard let expanded, document?.selected?.sha == expanded, let details = document?.details else { return }
        files = details.files
        reload()
    }

    /// A click: a commit opens or closes, a file opens its diff.
    @objc func clicked(_ sender: Any?) {
        guard let row = table?.clickedRow else { return }
        press(row)
    }

    func press(_ row: Int) {
        guard row >= 0, row < items.count else { return }
        switch items[row] {
        case .commit(let index):
            let commit = commits[index]
            if expanded == commit.sha {
                expanded = nil
                files = []
            } else {
                expanded = commit.sha
                files = []
                document?.select(commit)
            }
            reload()
        case .file(_, let index):
            document?.openDiff(files[index])
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .file(_, let file) = items[row] { return Self.fileHeight(last: file == files.count - 1) }
        return Self.commitHeight
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let index: Int
        switch item { case .commit(let i), .file(let i, _): index = i }
        let filtering = document?.searchResults == nil && document?.filter.isEmpty == false
        if index >= commits.count - HistoryRows.prefetch, !filtering {
            DispatchQueue.main.async { [weak self] in self?.document?.loadMore() }
        }
        let commit = commits[index]
        if tableColumn?.identifier.rawValue == "graph" {
            let view = tableView.makeView(withIdentifier: .init("graph"), owner: nil) as? HistoryGraphView ?? HistoryGraphView()
            view.identifier = .init("graph")
            if case .commit = item {
                view.graph = showsGraph ? commit.graph : nil
                view.passing = []
            } else {
                // The lanes the commit sends down keep going behind its files.
                view.graph = nil
                view.passing = showsGraph ? commit.graph?.bottom ?? [] : []
            }
            view.compact = true
            // The ring is filled with the row's ground: the open commit's is the chosen row's.
            view.ground = commit.sha == expanded ? DesignTokens.Inspector.Tree.Selected.bg : DesignTokens.Inspector.bg
            view.isMerge = commit.parents.count > 1
            view.isHead = commit.refs.contains { $0 == "HEAD" || $0.hasPrefix("HEAD -> ") }
            return view
        }
        if case .file(_, let file) = item { return fileCell(files[file], in: tableView) }
        return commitCell(commit, in: tableView)
    }

    private func commitCell(_ commit: HistoryCommit, in table: NSTableView) -> NSView {
        let cell = table.makeView(withIdentifier: .init("compactCommit"), owner: nil) as? HistoryCompactCell
            ?? HistoryCompactCell(identifier: "compactCommit")
        cell.top.attributedStringValue = Self.subject(commit)
        let when = Self.shortAge(commit.date)
        cell.bottom.stringValue = "\(commit.author) · \(when) · \(commit.shortSha)"
        HoverTip.attach(Self.tip(commit), to: cell)
        return cell
    }

    /// A file of the open commit as the drawing has it: the letter, the path, the counts on the right.
    private func fileCell(_ file: CommitDetails.File, in table: NSTableView) -> NSView {
        let cell = table.makeView(withIdentifier: .init("compactFile"), owner: nil) as? HistoryCompactFileCell
            ?? HistoryCompactFileCell()
        cell.show(file, color: Self.color(of: file.letter))
        HoverTip.attach(file.path, to: cell)
        return cell
    }

    /// "now", "4m", "1h", "yesterday", "3d": the History drawing's short ages ("17 minutes ago"
    /// took the meta line's room, 2026-11-17).
    static func shortAge(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return T("now", "agora") }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        if seconds < 2 * 86400 { return T("yesterday", "ontem") }
        return "\(seconds / 86400)d"
    }

    /// The hover tip of a commit: the whole subject, its branches and tags,
    /// who, when and the full SHA (the owner missed it, 2026-10-21).
    static func tip(_ commit: HistoryCommit) -> String {
        let refs = commit.refs.filter { $0 != "HEAD" }.map { $0.hasPrefix("HEAD -> ") ? String($0.dropFirst(8)) : $0 }
        var lines = [commit.subject]
        if !refs.isEmpty { lines.append(refs.joined(separator: ", ")) }
        lines.append(commit.email.isEmpty ? commit.author : "\(commit.author) <\(commit.email)>")
        lines.append(HistoryRows.fullDates.string(from: commit.date))
        lines.append(commit.sha)
        return lines.joined(separator: "\n")
    }

    static func color(of letter: Character) -> NSColor {
        switch letter {
        case "A": DesignTokens.Color.accentGreenText
        case "D": DesignTokens.Color.accentRedText
        case "R", "C": DesignTokens.Color.textTertiary
        default: DesignTokens.Color.accentAmberText
        }
    }

    /// The subject as the drawing has it: the subject in 13, medium, semibold on the commit you
    /// are on, then the branch and tag chips; one line, cut at the end.
    static func subject(_ commit: HistoryCommit) -> NSAttributedString {
        let head = commit.refs.contains { $0 == "HEAD" || $0.hasPrefix("HEAD -> ") }
        let font = UILooks.font(C.Title.fontSize, weight: head ? C.Title.headWeight : C.Title.weight)
        let text = NSMutableAttributedString(string: commit.subject, attributes: [.font: font, .foregroundColor: C.Title.color])
        for ref in commit.refs where ref != "HEAD" {
            let name = ref.hasPrefix("HEAD -> ") ? String(ref.dropFirst(8)) : ref.hasPrefix("tag: ") ? String(ref.dropFirst(5)) : ref
            // The drawing's 6 pt gap before each chip: a space of that width.
            text.append(NSAttributedString(string: " ", attributes: [.font: font, .kern: UILooks.pt(C.Ref.padding.left) - (" " as NSString).size(withAttributes: [.font: font]).width]))
            text.append(HistoryRefChip.make(name, besides: font))
        }
        let line = NSMutableParagraphStyle()
        line.lineBreakMode = .byTruncatingTail
        text.addAttribute(.paragraphStyle, value: line, range: NSRange(location: 0, length: text.length))
        return text
    }

    /// The open commit's row: the raised fill and its line (components.inspector.tree.selected).
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = HistoryCompactRowView()
        guard row < items.count else { return view }
        switch items[row] {
        case .commit(let index):
            if commits[index].sha == expanded { view.part = files.isEmpty ? .whole : .top }
        case .file(_, let file):
            view.part = file == files.count - 1 ? .bottom : .middle
        }
        return view
    }

    /// The right click: the commit becomes the selection, then each entry
    /// runs a registered command on it (ADR 0005).
    func menuEntries(_ row: Int) -> [MenuEntry] {
        guard row >= 0, row < items.count, case .commit(let index) = items[row] else { return [] }
        let commit = commits[index]
        if document?.selected != commit { document?.select(commit) }
        let entries: [(String, String, Icon)] = [
            (T("Show Commit Details in a Tab", "Mostrar o commit numa aba"), "history.show-in-tab", .arrowSquareOut),
            (T("Copy SHA", "Copiar sha"), "history.copy-sha", .copy),
            (T("Open on Remote", "Abrir no remoto"), "history.open-remote", .globe),
        ]
        return entries.map { title, id, icon in
            MenuEntry(title, icon: icon) { [weak self] in _ = self?.document?.runCommand?(id) }
        }
    }
}

