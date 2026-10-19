import AppKit

/// The history tab's view: search and "only the current branch" on top,
/// the commits with the graph, and the selected commit's details below.
@MainActor
final class HistoryView: NSView, NSSearchFieldDelegate {
    weak var document: HistoryDocument? {
        didSet { rows.document = document }
    }
    let searchField = NSSearchField()
    private let currentOnly = NSButton(checkboxWithTitle: "Só a branch atual", target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private let count = NSTextField(labelWithString: "")
    let table = NSTableView()
    private let rows = HistoryRows()
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
        let lanes = rows.showsGraph ? rows.commits.lazy.compactMap(\.graph?.width).max() ?? 1 : 0
        let graphColumn = table.tableColumns[0]
        graphColumn.isHidden = !rows.showsGraph
        graphColumn.width = HistoryGraphView.width(lanes: lanes)
        table.reloadData()
        if let sha = document.selected?.sha, let row = rows.commits.firstIndex(where: { $0.sha == sha }) {
            rows.selecting = true
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            rows.selecting = false
        }
        currentOnly.state = document.currentOnly ? .on : .off
        let n = rows.commits.count
        count.stringValue = document.searchResults != nil ? "\(n) encontrados" : n == 1 ? "1 commit" : "\(n) commits"
        switch document.state {
        case .loading where document.commits.isEmpty: empty.stringValue = "Carregando o histórico…"
        case .empty: empty.stringValue = "Nenhum commit ainda"
        case .failed: empty.stringValue = "Não foi possível ler o histórico deste repositório"
        default: empty.stringValue = ""
        }
        empty.isHidden = empty.stringValue.isEmpty
    }

    func showDetails() {
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
        searchField.placeholderString = "Filtrar por assunto, autor ou sha (Enter busca no repositório)"
        searchField.delegate = self
        searchField.sendsWholeSearchString = false
        currentOnly.target = self
        currentOnly.action = #selector(toggleCurrentOnly(_:))
        currentOnly.font = .systemFont(ofSize: 12)
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        count.font = .systemFont(ofSize: 11)
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
            // A third for the details. A split view put its divider at the
            // bottom and hid them, as it hid a side of the diff (2026-10-19).
            detailsView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            detailsView.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailsView.trailingAnchor.constraint(equalTo: trailingAnchor),
            detailsView.bottomAnchor.constraint(equalTo: bottomAnchor),
            detailsView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.34),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
    }
}
