import AppKit
import Worktrees
import CommandPalette
import Explorer
import GitHistory
import Icons
import Inspector
import Settings
import Memory
import SourceControl
import Strings
import UILooks

/// The side column's pages in this window (the right panel's tabs until ADR 0038) (docs/spec/inspector.md; plan 26 phase C): Changes, Files,
/// History and Memory, the pages the sidebar had, each from its feature; a tab's click runs its
/// command (ADR 0005) and the commands open the panel on it.
extension WindowSession {
    func makeInspector(explorer: ExplorerController, git: SourceControlController) -> InspectorView {
        // The order of use (ADR 0038): Files, Changes, Sessions, Memory, then the graph, the least used.
        let tabs = [
            InspectorTab(id: "files", title: T("Files", "Arquivos"), icon: .folder, command: "explorer.focus", view: explorer.view, actions: [
                InspectorAction("explorer.new-file", .filePlus, T("New File", "Novo arquivo")),
                InspectorAction("explorer.new-folder", .folderPlus, T("New Folder", "Nova pasta")),
                InspectorAction("explorer.collapse-all", .arrowsInLineVertical, T("Collapse All Folders", "Recolher todas as pastas")),
            ], more: [
                InspectorAction("search.files", .magnifyingGlass, T("Find File", "Buscar arquivo")),
                InspectorAction("explorer.refresh", .arrowsClockwise, T("Reload", "Recarregar")),
            ]),
            InspectorTab(id: "changes", title: T("Changes", "Mudanças"), icon: .gitDiff, command: "git.show", view: git.view, actions: [
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
            // The project's conversations (plan 36 C): the history read only while this shows.
            InspectorTab(id: "sessions", title: T("Sessions", "Sessões"), icon: .chatsCircle, command: "project.sessions-column",
                         view: makeSessionsColumn(), actions: [], more: [
                InspectorAction("project.show-sessions", .arrowSquareOut, T("All Sessions in the Project Page", "Todas as sessões na página do projeto")),
            ]),
            // Every action by its name in the "…" menu: three bare icons (sparkle, reload, eye) said
            // nothing (the owner, 2026-11-18).
            InspectorTab(id: "memory", title: T("Memory", "Memória"), icon: .brain, command: "memory.show", view: makeMemoryPage(), actions: [], more: [
                InspectorAction("memory.show-briefing", .eye, T("What the Agent Will See", "O que o agente vai ver")),
                InspectorAction("memory.bootstrap", .sparkle, T("Organize History with AI", "Organizar o histórico com IA")),
                InspectorAction("memory.reindex", .arrowsClockwise, T("Reindex", "Reindexar")),
                InspectorAction("memory.show-history", .clockCounterClockwise, T("Show Memory History", "Mostrar o histórico da memória")),
                InspectorAction("memory.pause-agent", .slidersHorizontal, T("Pause or Resume the Memory Agent", "Pausar ou retomar o agente de memória")),
                InspectorAction("memory.refresh", .arrowClockwise, T("Refresh", "Atualizar")),
            ]),
            InspectorTab(id: "history", title: T("Git Graph", "Grafo do git"), icon: .gitBranch, command: "git.show-history", view: panelHistoryHost, actions: [
                InspectorAction("git.history-in-tab", .arrowSquareOut, T("Open Git History in New Tab", "Abrir o histórico do git em nova aba")),
            ]),
        ]
        let shortcut = app.keymapLabel("inspector.toggle") ?? "⌥⌘I"
        // The pages' icons are the rail's (ADR 0038, revised 2026-11-18): none on top of the column.
        let inspector = InspectorView(tabs: tabs, shortcut: shortcut, tabsOnTop: false) { [weak self] id in _ = self?.commands.run(id) }
        inspector.onShow = { [weak self] id in
            if id == "history" { self?.showHistoryTab() }
            self?.workspace?.syncRailPages()
            if id == "sessions" { self?.showSessionsColumn() }
            self?.settings.store.update { $0.inspector.tab = id }
        }
        git.onBusy = { [weak inspector] busy in inspector?.setBusy(busy, for: "changes") }
        // The edge: the width follows the pointer within the settings' range, and is saved when let go.
        inspector.onResize = { [weak self] asked, ended in
            guard let self, let workspace = self.workspace else { return }
            let range = Settings.inspectorWidths
            let width = min(max(asked, UILooks.pt(range.lowerBound)), UILooks.pt(range.upperBound))
            workspace.setInspector(width: width)
            if ended { self.settings.store.update { $0.inspector.width = Double(width / UILooks.pt(1)) } }
        }
        return inspector
    }

    /// ⌃⌘1 to ⌃⌘4: the column's pages in order (plan 26 phase E; the sidebar.page-N ids of the old
    /// sidebar left in plan 27 phase D).
    func inspectorTabCommands() -> [Command] {
        (1...5).map { n in
            Command(id: "inspector.tab-\(n)", title: T("Go to Side Column Page \(n)", "Ir para a página \(n) da coluna lateral"),
                    keywords: ["panel \(n)", "tab \(n)", "inspector", "painel \(n)", "aba \(n)"], category: .view,
                    defaultShortcut: "ctrl+cmd+\(n)",
                    action: .run { [weak self] in
                        guard let workspace = self?.workspace, workspace.inspector.known.indices.contains(n - 1) else { return }
                        workspace.showInspector(workspace.inspector.known[n - 1])
                    },
                    unavailableReason: { [weak self] in
                        (self?.workspace?.inspector.known.count ?? 0) >= n ? nil : T("The panel has no tab \(n)", "O painel não tem a aba \(n)")
                    })
        }
    }

    /// inspector.visible and inspector.tab from settings, in this window.
    func applyInspector(_ prefs: Settings.Inspector) {
        guard let workspace else { return }
        // Always: the title bar's button lights with the panel open from the start too.
        workspace.setInspector(width: UILooks.pt(prefs.width))
        workspace.setInspector(visible: prefs.visible, launching: true)
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

    /// The scope row of Files and Memory and History, as the Inspector drawing has it: Files and
    /// History "orchestration-e · cadex.worktrees/orchestration-e" (the folder, then where it
    /// sits), Memory the project's name; the whole path in the tip.
    func showPanelFolder(_ root: String) {
        guard let inspector = workspace?.inspector else { return }
        let name = Self.folderName(root)
        let place = ((root as NSString).deletingLastPathComponent as NSString).lastPathComponent + "/" + name
        // The name alone, as the proposal's Files: "name · parent/name" repeated it, cut (2026-11-18).
        inspector.setScope(InspectorScope(name, tip: root), for: "files")
        inspector.setScope(InspectorScope(name + " · " + place, tip: root), for: "history")
        // A task's history: how far it went from where it started (the Inspector drawing,
        // "orchestration-e · 3 commits ahead of main"), counted by git off the main thread.
        if let base = WorktreesController.shared.store.task(root)?.base, !base.isEmpty {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let ahead = Self.commitsAhead(of: base, in: root)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, let ahead, self.folder.root == root else { return }
                        let words = ahead == 1 ? T("1 commit ahead of \(base)", "1 commit à frente de \(base)")
                            : T("\(ahead) commits ahead of \(base)", "\(ahead) commits à frente de \(base)")
                        self.workspace?.inspector.setScope(InspectorScope(name + " · " + words, tip: root), for: "history")
                    }
                }
            }
        }
        let project = TitleBarView.location(of: root).project
        // The project alone: the sentence was cut ("the project's me…"); it is in the tip.
        // The proposal's head: "What the project knows", the project under it in the tab.
        let memoryTip = project + " · " + root + "\n" + T("The project's memory, shared by every task and account",
                                                          "A memória do projeto, de todas as tarefas e contas")
        inspector.setScope(InspectorScope(T("What the project knows", "O que o projeto sabe"), tip: memoryTip, strong: true), for: "memory")
    }

    /// Changes' scope: the branch with ↑ and ↓, the click switches branch; "Git" outside a
    /// repository. From the status the panel reads anyway.
    func showPanelBranch(_ branch: SourceControlController.Branch?) {
        let name = Self.folderName(folder.root)
        // A task: what it is measured against (the Inspector drawing, "orchestration-e · against main").
        if let base = WorktreesController.shared.store.task(folder.root)?.base, !base.isEmpty {
            return workspace?.inspector.setScope(InspectorScope(name + T(" · against ", " · contra ") + base, command: "git.switch-branch",
                                                               tip: T("Switch branch", "Trocar de branch")), for: "changes") ?? ()
        }
        workspace?.inspector.setScope(branch.map {
            InspectorScope(name + " · " + Self.branchText($0), command: "git.switch-branch", tip: T("Switch branch", "Trocar de branch"))
        } ?? InspectorScope("Git"), for: "changes")
    }

    static func folderName(_ path: String) -> String { (path as NSString).lastPathComponent }

    /// `git rev-list --count <base>..HEAD` in `folder`; nil when git says no.
    nonisolated static func commitsAhead(of base: String, in folder: String) -> Int? {
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["-C", folder, "rev-list", "--count", base + "..HEAD"]
        let out = Pipe()
        git.standardOutput = out
        git.standardError = FileHandle.nullDevice
        guard (try? git.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        git.waitUntilExit()
        guard git.terminationStatus == 0 else { return nil }
        return Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

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
