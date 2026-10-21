import AppKit
import UILooks
import Menus
import Strings

/// The history tab's view: search and "only the current branch" on top,
/// the commits with the graph, and the selected commit's details below.
@MainActor
final class HistoryView: NSView, NSSearchFieldDelegate {
    weak var document: HistoryDocument? {
        didSet {
            rows.document = document
            compactRows.document = document
        }
    }
    let searchField = NSSearchField()
    private let currentOnly = NSButton(checkboxWithTitle: T("Current branch only", "Só a branch atual"), target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private let count = NSTextField(labelWithString: "")
    let table = MenuTableView()
    private let rows = HistoryRows()
    private let compactRows = HistoryCompactRows()
    private(set) var isCompact = false
    private var detailsShare: NSLayoutConstraint!
    private var detailsNone: NSLayoutConstraint!
    private let scroll = NSScrollView()
    let detailsView = HistoryDetailsView()
    private let separator = NSBox()
    private let empty = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("HistoryView is created in code") }

    func setBusy(_ busy: Bool) {
        busy ? progress.startAnimation(nil) : progress.stopAnimation(nil)
    }

    /// Redraws the list from the document, keeping the selected commit.
    func render() {
        guard let document else { return }
        rows.commits = document.shown
        rows.showsGraph = document.showsGraph
        compactRows.commits = rows.commits
        compactRows.showsGraph = rows.showsGraph
        let lanes = rows.showsGraph ? rows.commits.lazy.compactMap(\.graph?.width).max() ?? 1 : 0
        let graphColumn = table.tableColumns[0]
        graphColumn.isHidden = !rows.showsGraph
        graphColumn.width = HistoryGraphView.width(lanes: lanes)
        if isCompact { compactRows.reload() } else { table.reloadData() }
        if !isCompact, let sha = document.selected?.sha, let row = rows.commits.firstIndex(where: { $0.sha == sha }) {
            rows.selecting = true
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            rows.selecting = false
        }
        currentOnly.state = document.currentOnly ? .on : .off
        let n = rows.commits.count
        count.stringValue = document.searchResults != nil ? T("\(n) found", "\(n) encontrados") : n == 1 ? "1 commit" : "\(n) commits"
        switch document.state {
        case .loading where document.commits.isEmpty: empty.stringValue = T("Loading history…", "Carregando o histórico…")
        case .empty: empty.stringValue = T("No commits yet", "Nenhum commit ainda")
        case .failed: empty.stringValue = T("Couldn't read this repository's history", "Não foi possível ler o histórico deste repositório")
        default: empty.stringValue = ""
        }
        empty.isHidden = empty.stringValue.isEmpty
    }

    private var header: NSTableHeaderView?

    /// The sidebar's narrow look: the columns a pane of 240 points cannot
    /// show go, and so do the column titles, the checkbox and the count
    /// (the checkbox's command stays in ⌘K).
    func setCompact(_ compact: Bool) {
        if header == nil { header = table.headerView }
        table.headerView = compact ? nil : header
        for column in table.tableColumns where ["author", "date", "sha"].contains(column.identifier.rawValue) {
            column.isHidden = compact
        }
        currentOnly.isHidden = compact
        count.isHidden = compact
        searchField.placeholderString = compact
            ? T("Filter commits", "Filtrar commits")
            : T("Filter by subject, author or SHA (Enter searches the repository)", "Filtrar por assunto, autor ou sha (Enter busca no repositório)")
        table.sizeLastColumnToFit()
        detailsView.setCompact(compact)
        // The sidebar's rows: two lines per commit, files opening under it,
        // and no details pane (HistoryCompactRows).
        isCompact = compact
        table.dataSource = compact ? compactRows : rows
        table.delegate = compact ? compactRows : rows
        table.contextEntries = compact
            ? { [weak self] row in self?.compactRows.menuEntries(row) ?? [] }
            : { [weak self] row in self?.rows.menuEntries(row) ?? [] }
        table.target = compact ? compactRows : nil
        table.action = compact ? #selector(HistoryCompactRows.clicked(_:)) : nil
        compactRows.table = table
        separator.isHidden = compact
        detailsView.isHidden = compact
        detailsShare.isActive = !compact
        detailsNone.isActive = compact
        render()
    }

    func showDetails() {
        if isCompact { return compactRows.detailsArrived() }
        detailsView.show(document?.selected, details: document?.details)
    }

    // MARK: Search

    func controlTextDidChange(_ obj: Notification) {
        document?.setFilter(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        document?.searchRepository(searchField.stringValue)
        return true
    }

    @objc private func toggleCurrentOnly(_ sender: NSButton) {
        _ = document?.runCommand?("history.current-branch")
    }

    // MARK: Layout

    private func build() {
        searchField.placeholderString = T("Filter by subject, author or SHA (Enter searches the repository)", "Filtrar por assunto, autor ou sha (Enter busca no repositório)")
        searchField.delegate = self
        searchField.sendsWholeSearchString = false
        currentOnly.target = self
        currentOnly.action = #selector(toggleCurrentOnly(_:))
        currentOnly.font = UILooks.font(12)
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        count.font = UILooks.font(11)
        count.textColor = .secondaryLabelColor
        let top = NSStackView(views: [searchField, currentOnly, progress, count])
        top.spacing = 10
        top.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        rows.table = table
        rows.build()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        detailsView.onOpenFile = { [weak self] file in self?.document?.openDiff(file) }
        separator.boxType = .separator

        empty.textColor = .secondaryLabelColor
        empty.alignment = .center
        for v in [top, scroll, separator, detailsView, empty] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        detailsShare = detailsView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.34)
        detailsNone = detailsView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            top.leadingAnchor.constraint(equalTo: leadingAnchor),
            top.trailingAnchor.constraint(equalTo: trailingAnchor),
            // Without a height the bar took the free space and the list
            // none (2026-10-19).
            top.heightAnchor.constraint(equalToConstant: 28),
            scroll.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            // One point: without it, in the sidebar's narrow page the
            // separator took the free height, drew upright and left the list
            // none (owner's print, 2026-10-21).
            separator.heightAnchor.constraint(equalToConstant: 1),
            // A third for the details. A split view put its divider at the
            // bottom and hid them, as it hid a side of the diff (2026-10-19).
            detailsView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            detailsView.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailsView.trailingAnchor.constraint(equalTo: trailingAnchor),
            detailsView.bottomAnchor.constraint(equalTo: bottomAnchor),
            detailsShare,
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
    }
}
