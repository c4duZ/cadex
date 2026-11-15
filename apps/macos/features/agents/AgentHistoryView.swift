import AppKit
import Menus
import Strings
import UILooks

/// Agents › History (docs/spec/agents.md, Histórico): every conversation of
/// every account, searchable by title, folder, branch and what was said,
/// grouped by project, folder or account, in this project or all. Reads
/// only while it shows.
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
    let scope = NSPopUpButton()
    let grouping = NSPopUpButton()
    let table = AgentHistoryTable()
    private let scroll = NSScrollView()
    private let note = NSTextField(wrappingLabelWithString: "")
    private let enable = NSButton()
    private var token: UUID?
    private var matches: Set<String>?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        search.placeholderString = T("Search conversations", "Buscar conversas")
        search.target = self
        search.action = #selector(searchChanged)
        scope.addItems(withTitles: [T("This Project", "Este projeto"), T("All Projects", "Todos os projetos")])
        scope.selectItem(at: 1)
        grouping.addItems(withTitles: [T("By Project", "Por projeto"), T("By Folder", "Por pasta"), T("By Account", "Por conta")])
        for popup in [scope, grouping] {
            popup.controlSize = .small
            popup.target = self
            popup.action = #selector(render)
        }
        enable.title = T("Turn On", "Ligar")
        enable.bezelStyle = .rounded
        enable.target = self
        enable.action = #selector(enableClicked)
        note.font = UILooks.font(11)
        table.onResume = { [weak self] entry in self?.onResume?(entry) }
        table.menuFor = { [weak self] entry in self?.menu(entry) ?? [] }
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        layout(views: [search, NSStackView(views: [scope, grouping]), note, enable, scroll])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func layout(views: [NSView]) {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            search.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16),
        ])
    }

    /// Reads only while on screen: the watch starts with the window and stops without it.
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, token == nil {
            token = history.watch { [weak self] in self?.render() }
        } else if window == nil, let id = token {
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

    @objc private func enableClicked() { onEnable?() }

    @objc func render() {
        let grouping = AgentHistoryGrouping.allCases[max(0, self.grouping.indexOfSelectedItem)]
        let project = scope.indexOfSelectedItem == 0 ? project?() : nil
        table.items = history.isEnabled
            ? AgentHistoryRows.make(history.entries, query: search.stringValue, matches: matches, project: project,
                                    grouping: grouping, accountName: accountName)
            : []
        enable.isHidden = history.isEnabled
        note.textColor = colors.secondary
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
