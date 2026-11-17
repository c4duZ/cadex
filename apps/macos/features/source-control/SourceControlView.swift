import AppKit
import UILooks
import Icons
import Menus
import Strings

/// The Changes tab of the right panel (docs/spec/inspector.md, Changes; the Inspector mockup;
/// plan 26 phase C2): Last turn / Task / Uncommitted on top, one row per changed file, and the
/// footer with Commit… and Open PR. The branch and the sync buttons are in the panel's scope row,
/// which the app fills from onBranch and onBusy. Every click runs a command by id (ADR 0005).
@MainActor
final class SourceControlView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    typealias I = DesignTokens.Inspector
    weak var controller: SourceControlController?
    let table = MenuTableView()
    private let scroll = NSScrollView()
    let segmented = ChangesSegmented()
    private let footer = NSStackView()
    private let error = NSTextField(wrappingLabelWithString: "")
    private let empty = NSTextField(wrappingLabelWithString: "")
    private lazy var initButton = DesignButton.make(T("Initialize Repository", "Inicializar repositório"), .secondary) { [weak self] in
        self?.controller?.initRepository()
    }
    /// "No changes" over the empty list, that no agent turn was seen in this repository, or why the
    /// list could not be read.
    private let none = NSTextField(wrappingLabelWithString: "")
    /// "N more" past the 500 rows (docs/spec/inspector.md).
    private let more = NSTextField(labelWithString: "")

    /// On screen: the list reads only then (SourceControlChanges.loadChanges).
    var shows: Bool { window != nil && !isHiddenOrHasHiddenAncestor }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        if controller?.changesStale == true { controller?.loadChanges() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if controller?.changesStale == true { controller?.loadChanges() }
    }
    private(set) var rows: [ChangesRow] = []

    init() {
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SourceControlView is created in code") }

    func show(error text: String?) {
        error.stringValue = text ?? ""
        error.isHidden = text == nil
    }

    /// Redraws the states from the controller (the list follows in renderChanges).
    func render() {
        guard let controller else { return }
        let ready = controller.state == .ready || controller.state == .loading && controller.repo != nil
        [segmented, scroll, footer].forEach { $0.isHidden = !ready }
        if !ready { none.isHidden = true }
        empty.isHidden = ready
        initButton.isHidden = controller.state != .noRepository
        switch controller.state {
        case .gitMissing: empty.stringValue = T("Git was not found.\nInstall it with:\nxcode-select --install", "O git não foi encontrado.\nInstale com:\nxcode-select --install")
        case .noRepository: empty.stringValue = T("Not a Git repository", "Não é um repositório Git")
        case .loading where controller.repo == nil: empty.stringValue = T("Looking for the repository…", "Procurando o repositório…")
        default: empty.stringValue = ""
        }
        segmented.select(controller.scope)
    }

    /// The scope's files, read after the status.
    func renderChanges(turnSeen: Bool, problem: String?) {
        guard let controller else { return }
        rows = controller.changeRows
        table.reloadData()
        segmented.select(controller.scope)
        let hidden = controller.changeTotal - rows.count
        more.stringValue = hidden > 0 ? T("\(hidden) more", "Mais \(hidden)") : ""
        more.isHidden = hidden <= 0
        let none: String? = problem ?? (rows.isEmpty
            ? (turnSeen ? T("No changes", "Nenhuma mudança") : T("No agent turn seen here yet", "Nenhuma rodada de agente vista aqui ainda")) : nil)
        self.none.stringValue = none ?? ""
        self.none.isHidden = none == nil || scroll.isHidden
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        ChangesRowView(rows[row])
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0, table.selectedRow < rows.count else { return }
        controller?.openChange(rows[table.selectedRow])
    }

    /// The entries the context menu acts on (the clicked row, or the selection), each with its
    /// side: a file with staged and unstaged changes counts on both.
    func selectedEntries() -> [(GitRepository.Entry, Bool)] {
        let clicked = table.menuRow
        let indexes = clicked >= 0 && !table.selectedRowIndexes.contains(clicked) ? IndexSet(integer: clicked) : table.selectedRowIndexes
        return indexes.filter { $0 < rows.count }.flatMap { i -> [(GitRepository.Entry, Bool)] in
            guard let entry = rows[i].entry else { return [] }
            return (entry.isUnstaged || entry.kind == .conflict ? [(entry, false)] : []) + (entry.isStaged ? [(entry, true)] : [])
        }
    }

    // MARK: Layout

    private func build() {
        table.addTableColumn(NSTableColumn(identifier: .init("change")))
        table.headerView = nil
        table.rowHeight = UILooks.rowHeight(I.FileRow.height)
        table.style = .plain
        table.backgroundColor = .clear
        table.allowsMultipleSelection = true
        table.dataSource = self
        table.delegate = self
        table.contextEntries = { [weak self] _ in self.map(SourceControlMenu.entries) ?? [] }
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        segmented.onPick = { [weak self] scope in _ = self?.controller?.run(scope.command) }

        // The footer: the project's check line waits for a source of it (docs/spec/inspector.md);
        // Commit… asks the message, Open PR opens the GitHub CLI in a tab.
        typealias Large = DesignTokens.Button.Heights
        let commit = DesignButton.make(T("Commit…", "Commit…"), .secondary, height: Large.large, fill: true) { [weak self] in
            _ = self?.controller?.run("git.commit")
        }
        let pr = DesignButton.make(T("Open PR", "Abrir PR"), .primary, height: Large.large, fill: true) { [weak self] in
            _ = self?.controller?.run("git.open-pr")
        }
        let buttons = NSStackView(views: [commit, pr])
        buttons.distribution = .fillEqually
        buttons.spacing = UILooks.pt(I.Footer.gap)
        // The error over the buttons; hidden, the stack lets go of its room.
        more.font = UILooks.font(DesignTokens.FontSize.meta)
        more.textColor = DesignTokens.Color.textMuted
        more.isHidden = true
        footer.setViews([more, error, buttons], in: .top)
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.detachesHiddenViews = true
        footer.spacing = UILooks.pt(I.Footer.gap)
        buttons.widthAnchor.constraint(equalTo: footer.widthAnchor, constant: -UILooks.pt(I.Footer.padding) * 2).isActive = true
        error.widthAnchor.constraint(equalTo: buttons.widthAnchor).isActive = true
        footer.edgeInsets = NSEdgeInsets(top: UILooks.pt(I.Footer.padding), left: UILooks.pt(I.Footer.padding),
                                         bottom: UILooks.pt(I.Footer.padding), right: UILooks.pt(I.Footer.padding))
        let footerLine = NSView()
        footerLine.wantsLayer = true
        footerLine.layer?.backgroundColor = I.Footer.borderTop.cgColor

        error.font = UILooks.font(DesignTokens.FontSize.meta)
        error.textColor = DesignTokens.Color.accentRedText
        error.isHidden = true
        empty.alignment = .center
        empty.font = UILooks.font(DesignTokens.FontSize.body)
        empty.textColor = DesignTokens.Color.textMuted
        none.alignment = .center
        none.font = UILooks.font(DesignTokens.FontSize.body)
        none.textColor = DesignTokens.Color.textMuted
        none.isHidden = true

        for v in [segmented, scroll, footerLine, footer, empty, initButton, none] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        let margin = I.Segmented.margin
        NSLayoutConstraint.activate([
            segmented.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(margin.top)),
            segmented.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(margin.left)),
            segmented.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(margin.right)),
            scroll.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: UILooks.pt(margin.bottom)),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerLine.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            footerLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerLine.heightAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline),
            footer.topAnchor.constraint(equalTo: footerLine.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
            empty.centerYAnchor.constraint(equalTo: centerYAnchor),
            empty.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(I.Footer.padding)),
            empty.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(I.Footer.padding)),
            initButton.topAnchor.constraint(equalTo: empty.bottomAnchor, constant: UILooks.pt(I.Footer.padding)),
            initButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            none.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            none.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(I.Footer.padding)),
            none.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(I.Footer.padding)),
        ])
    }
}

extension ChangesScope {
    /// The command each segment runs (ADR 0005).
    var command: String {
        switch self {
        case .lastTurn: "git.changes-last-turn"
        case .task: "git.changes-task"
        case .uncommitted: "git.changes-uncommitted"
        }
    }
}
