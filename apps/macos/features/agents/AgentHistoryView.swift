import AppKit
import Menus
import Strings
import UILooks

/// Archive & history (docs/spec/agents.md, Histórico): every conversation of
/// every account, searchable by title, folder, branch and what was said,
/// grouped by project, folder or account, in this project or all. Reads
/// only while it shows. A page in the project page's face (plan 31 C): the
/// title and the count, the search in the frame's box, the scope and the
/// grouping as the board's pills, each conversation a row of the project
/// page's list under its group's label.
@MainActor
public final class AgentHistoryView: NSView {
    public var colors = AgentColors() { didSet { table.colors = colors; render() } }
    /// This window's project (git root), for the "This Project" scope.
    public var project: (() -> String)?
    public var accountName: (String) -> String = { ($0 as NSString).lastPathComponent } {
        didSet { table.accountName = accountName }
    }
    public var onResume: ((AgentHistoryEntry) -> Void)?
    public var onContinue: ((AgentHistoryEntry) -> Void)?
    public var onCopyCommand: ((AgentHistoryEntry) -> Void)?
    public var onReveal: ((AgentHistoryEntry) -> Void)?
    public var onOpenFolder: ((AgentHistoryEntry) -> Void)?
    public var onEnable: (() -> Void)?

    let history = AgentHistoryController.shared
    let search = NSSearchField()
    /// 0 this project, 1 all; the grouping's index in AgentHistoryGrouping.
    private(set) var scopeIndex = 1
    private(set) var groupingIndex = 0
    let table = AgentHistoryTable()
    private let scroll = NSScrollView()
    private let note = NSTextField(wrappingLabelWithString: "")
    private let count = FrameField.text("", color: DesignTokens.Project.Head.meta)
    private let pills = NSStackView()
    private var enable: NSView?
    private var token: UUID?
    private var matches: Set<String>?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = DesignTokens.Color.bgWindow.cgColor
        search.placeholderString = T("Search conversations", "Buscar conversas")
        search.target = self
        search.action = #selector(searchChanged)
        let enable = DesignButton.make(T("Turn On", "Ligar"), .primary) { [weak self] in self?.onEnable?() }
        self.enable = enable
        note.font = UILooks.font(DesignTokens.FontSize.meta)
        table.onResume = { [weak self] entry in self?.onResume?(entry) }
        table.menuFor = { [weak self] entry in self?.menu(entry) ?? [] }
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        pills.spacing = UILooks.pt(DesignTokens.Board.Filters.gap)
        let title = FrameField.text(T("All sessions", "Todas as sessões"), size: DesignTokens.Project.Title.fontSize,
                                    color: DesignTokens.Color.textPrimary, weight: DesignTokens.Project.Title.weight)
        let head = FrameField.column([title, count], gap: DesignTokens.Project.Head.titleGap)
        let field = FrameField.field(search)
        field.widthAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Inspector.width)).isActive = true
        // The search, then the pills on a line of their own: beside the search they were cut on a
        // window with the right panel open (2026-11-18).
        let controls = FrameField.column([field, pills], gap: DesignTokens.Project.Columns.listGap * 2)
        layout(views: [head, controls, note, enable, scroll])
        showPills()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func layout(views: [NSView]) {
        let pad = DesignTokens.Project.padding
        let stack = FrameField.column(views, gap: DesignTokens.Project.Columns.listGap * 2)
        stack.edgeInsets = NSEdgeInsets(top: UILooks.pt(pad.top), left: UILooks.pt(pad.left), bottom: 0, right: UILooks.pt(pad.right))
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for view in views where view !== enable {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -UILooks.pt(pad.left + pad.right)).isActive = true
        }
    }

    /// This project · All projects, then By project · By folder · By account.
    private func showPills() {
        pills.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let scopes = [T("This project", "Este projeto"), T("All projects", "Todos os projetos")]
        let groups = [T("By project", "Por projeto"), T("By folder", "Por pasta"), T("By account", "Por conta")]
        for (index, title) in scopes.enumerated() {
            pills.addArrangedSubview(FramePill.make(title, on: index == scopeIndex) { [weak self] in self?.scopeIndex = index; self?.showPills(); self?.render() })
        }
        let gap = NSView()
        gap.widthAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Project.Head.gap)).isActive = true
        pills.addArrangedSubview(gap)
        for (index, title) in groups.enumerated() {
            pills.addArrangedSubview(FramePill.make(title, on: index == groupingIndex) { [weak self] in self?.groupingIndex = index; self?.showPills(); self?.render() })
        }
    }

    /// Reads only while on screen: in a window and not hidden. The sidebar
    /// keeps every page in the window and hides the others, so the window
    /// alone indexed with the page closed (make perf, 2026-11-14).
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWatching()
    }

    public override func viewDidHide() {
        super.viewDidHide()
        updateWatching()
    }

    public override func viewDidUnhide() {
        super.viewDidUnhide()
        updateWatching()
    }

    func updateWatching() {
        let shows = window != nil && !isHiddenOrHasHiddenAncestor
        if shows, token == nil {
            token = history.watch { [weak self] in self?.render() }
        } else if !shows, let id = token {
            history.stop(id)
            token = nil
        }
    }

    @objc private func searchChanged() {
        let words = search.stringValue
        guard !words.trimmingCharacters(in: .whitespaces).isEmpty else {
            matches = nil
            return render()
        }
        history.search(words) { [weak self] found in
            guard let self, self.search.stringValue == words else { return }
            self.matches = found
            self.render()
        }
        render()
    }

    @objc func render() {
        let grouping = AgentHistoryGrouping.allCases[groupingIndex]
        let project = scopeIndex == 0 ? project?() : nil
        table.items = history.isEnabled
            ? AgentHistoryRows.make(history.entries, query: search.stringValue, matches: matches, project: project,
                                    grouping: grouping, accountName: accountName)
            : []
        enable?.isHidden = history.isEnabled
        note.textColor = DesignTokens.Color.textMuted
        let conversations = table.items.filter { if case .entry = $0 { return true }; return false }.count
        count.stringValue = T("\(conversations) conversations · every account on this Mac", "\(conversations) conversas · todas as contas deste Mac")
        if !history.isEnabled {
            note.stringValue = T("History is off (agents.history): nothing is indexed or watched.",
                                 "O histórico está desligado (agents.history): nada é indexado nem vigiado.")
        } else if let progress = history.progress {
            note.stringValue = T("Indexing \(progress.done) of \(progress.total)", "Indexando \(progress.done) de \(progress.total)")
        } else if table.items.isEmpty {
            note.stringValue = history.entries.isEmpty
                ? T("No conversations yet. Start one in a terminal: claude", "Nenhuma conversa ainda. Comece uma num terminal: claude")
                : T("Nothing matches.", "Nada corresponde.")
        } else if history.unreadable > 0 {
            // The format changed in a newer Claude Code: what read is shown, the rest is skipped.
            note.stringValue = T("Some lines could not be read (\(history.unreadable)).", "Algumas linhas não deu para ler (\(history.unreadable)).")
        } else {
            note.stringValue = ""
        }
        note.isHidden = note.stringValue.isEmpty
    }

    func menu(_ entry: AgentHistoryEntry) -> [MenuEntry] {
        [MenuEntry(T("Resume", "Retomar"), icon: .terminalWindow) { [weak self] in self?.onResume?(entry) },
         MenuEntry(T("Continue in Another Account…", "Continuar em outra conta…"), icon: .arrowSquareOut) { [weak self] in self?.onContinue?(entry) },
         MenuEntry(T("Copy Resume Command", "Copiar o comando de retomar"), icon: .copy) { [weak self] in self?.onCopyCommand?(entry) },
         MenuEntry(T("Reveal Session Log", "Mostrar o arquivo da sessão"), icon: .file) { [weak self] in self?.onReveal?(entry) },
         MenuEntry(T("Open Its Folder in the Workspace", "Abrir a pasta dela no workspace"), icon: .folderOpen) { [weak self] in self?.onOpenFolder?(entry) }]
    }
}
