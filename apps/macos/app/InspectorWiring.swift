import AppKit
import Explorer
import GitHistory
import Icons
import Inspector
import Settings
import Memory
import SourceControl
import Strings

/// The right panel's tabs in this window (docs/spec/inspector.md; plan 26 phase C): Changes, Files,
/// History and Memory, the pages the sidebar had, each from its feature; a tab's click runs its
/// command (ADR 0005) and the commands open the panel on it.
extension WindowSession {
    func makeInspector(explorer: ExplorerController, git: SourceControlController) -> InspectorView {
        let tabs = [
            InspectorTab(id: "changes", title: T("Changes", "Mudanças"), command: "git.show", view: git.view, actions: [
                InspectorAction("git.fetch", .arrowsClockwise, "Fetch"),
                InspectorAction("git.pull", .arrowDown, "Pull"),
                InspectorAction("git.push", .arrowUp, "Push"),
                InspectorAction("git.review-open", .gitDiff, T("Review Changes", "Revisar as mudanças")),
            ], more: [
                InspectorAction("git.switch-branch", .gitBranch, T("Switch Branch…", "Trocar de branch…")),
                InspectorAction("git.stage-all", .plus, T("Stage All", "Adicionar tudo ao stage")),
                InspectorAction("git.unstage-all", .minus, T("Unstage All", "Tirar tudo do stage")),
                InspectorAction("git.refresh", .arrowClockwise, T("Refresh", "Atualizar")),
            ]),
            InspectorTab(id: "files", title: T("Files", "Arquivos"), command: "explorer.focus", view: explorer.view, actions: [
                InspectorAction("explorer.new-file", .filePlus, T("New File", "Novo arquivo")),
                InspectorAction("explorer.new-folder", .folderPlus, T("New Folder", "Nova pasta")),
                InspectorAction("explorer.collapse-all", .arrowsInLineVertical, T("Collapse All Folders", "Recolher todas as pastas")),
            ], more: [
                InspectorAction("search.files", .magnifyingGlass, T("Find File", "Buscar arquivo")),
                InspectorAction("explorer.refresh", .arrowsClockwise, T("Reload", "Recarregar")),
            ]),
            InspectorTab(id: "history", title: T("History", "Histórico"), command: "git.show-history", view: panelHistoryHost, actions: [
                InspectorAction("git.history-in-tab", .arrowSquareOut, T("Open Git History in New Tab", "Abrir o histórico do git em nova aba")),
            ]),
            InspectorTab(id: "memory", title: T("Memory", "Memória"), command: "memory.show", view: makeMemoryPage(), actions: [
                InspectorAction("memory.bootstrap", .sparkle, T("Organize History with AI", "Organizar o histórico com IA")),
                InspectorAction("memory.reindex", .arrowsClockwise, T("Reindex", "Reindexar")),
                InspectorAction("memory.show-briefing", .eye, T("What the Agent Will See", "O que o agente vai ver")),
            ], more: [
                InspectorAction("memory.show-history", .clockCounterClockwise, T("Show Memory History", "Mostrar o histórico da memória")),
                InspectorAction("memory.pause-agent", .slidersHorizontal, T("Pause or Resume the Memory Agent", "Pausar ou retomar o agente de memória")),
                InspectorAction("memory.refresh", .arrowClockwise, T("Refresh", "Atualizar")),
            ]),
        ]
        let shortcut = app.keymapLabel("inspector.toggle") ?? "⌥⌘I"
        let inspector = InspectorView(tabs: tabs, shortcut: shortcut) { [weak self] id in _ = self?.commands.run(id) }
        inspector.onShow = { [weak self] id in
            if id == "history" { self?.showHistoryTab() }
            self?.settings.store.update { $0.inspector.tab = id }
        }
        git.onBusy = { [weak inspector] busy in inspector?.setBusy(busy, for: "changes") }
        return inspector
    }

    /// inspector.visible and inspector.tab from settings, in this window.
    func applyInspector(_ prefs: Settings.Inspector) {
        guard let workspace else { return }
        // Always: the title bar's button lights with the panel open from the start too.
        workspace.setInspector(visible: prefs.visible)
        // Closed: the tab is only picked, so nothing reads behind a hidden panel.
        if workspace.inspector.tab != prefs.tab { workspace.inspector.show(prefs.tab, announce: prefs.visible) }
    }

    /// inspector.toggle (⌥⌘I, the title bar's button): saved, so it comes back on reopen.
    func toggleInspector() {
        guard let workspace else { return }
        workspace.setInspector(visible: !workspace.inspectorVisible)
        let visible = workspace.inspectorVisible
        settings.store.update { $0.inspector.visible = visible }
    }

    /// The scope row of Files and Memory and History: the folder's name, the whole path in the tip.
    func showPanelFolder(_ root: String) {
        guard let inspector = workspace?.inspector else { return }
        let name = Self.folderName(root)
        inspector.setScope(InspectorScope(name, tip: root), for: "files")
        inspector.setScope(InspectorScope(name, tip: root), for: "history")
        inspector.setScope(InspectorScope(name + T(" · the project’s memory, shared by every task and account",
                                                   " · a memória do projeto, de todas as tarefas e contas"), tip: root), for: "memory")
    }

    /// Changes' scope: the branch with ↑ and ↓, the click switches branch; "Git" outside a
    /// repository. From the status the panel reads anyway.
    func showPanelBranch(_ branch: SourceControlController.Branch?) {
        workspace?.inspector.setScope(branch.map {
            InspectorScope(Self.branchText($0), command: "git.switch-branch", tip: T("Switch branch", "Trocar de branch"))
        } ?? InspectorScope("Git"), for: "changes")
    }

    static func folderName(_ path: String) -> String { (path as NSString).lastPathComponent }

    /// The History tab: the repository's history, compact, made the
    /// first time the tab shows and again when the repository changes.
    /// Outside a repository the tab says so. The root comes from git, off
    /// the main thread (source-control's rule).
    func showHistoryTab() {
        let folder = self.folder.root
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let root = SourceControlController.repositoryRoot(containing: folder)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.folder.root == folder else { return }
                    self.placeHistoryTab(root)
                }
            }
        }
    }

    private func placeHistoryTab(_ root: String?) {
        if let current = panelHistory, current.root == root { return }
        panelHistory?.view.removeFromSuperview()
        panelHistory = nil
        panelHistoryHost.subviews.forEach { $0.removeFromSuperview() }
        guard let root, let opener else {
            let label = NSTextField(labelWithString: T("Not a Git repository", "Não é um repositório Git"))
            label.textColor = .secondaryLabelColor
            fill(panelHistoryHost, with: label, centered: true)
            return
        }
        let history = opener.makeHistory(root)
        history.compact = true
        panelHistory = history
        fill(panelHistoryHost, with: history.view, centered: false)
    }

    /// The workspace moved: the page follows, if it was ever opened.
    func panelFolderChanged() {
        guard panelHistory != nil || !panelHistoryHost.subviews.isEmpty else { return }
        if workspace?.inspectorVisible == true, workspace?.inspector.tab == "history" { showHistoryTab() } else {
            panelHistory?.view.removeFromSuperview()
            panelHistory = nil
            panelHistoryHost.subviews.forEach { $0.removeFromSuperview() }
        }
    }

    private func fill(_ host: NSView, with view: NSView, centered: Bool) {
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate(centered ? [
            view.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: host.centerYAnchor),
        ] : [
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
    }

}
