import AgentTools
import ComputerUse
import Agents
import AppKit
import Orchestration
import Worktrees
import CommandPalette
import Editor
import Explorer
import GitHistory
import Machines
import Markdown
import MediaPreview
import Memory
import Power
import Preview
import Search
import Settings
import SSH
import Sidebar
import SourceControl
import StatusBar
import Strings
import Tabs
import Terminal
import Updates

/// Every feature registers its commands in the window's registry; the menu
/// and the shortcuts come from it (ADR 0005). Each window has its own, so
/// a command acts on the window it ran in.
extension WindowSession {
    func setUpCommands() {
        // The palette shows each command's shortcut, which settings can
        // change; it reads the current one from the app.
        let palette = CommandPaletteController(registry: commands) { [unowned app] in app.keymapLabel($0) }
        palette.home = window
        self.palette = palette
        commands.register(palette.openCommand)
        commands.register(StandardCommands.all)
        commands.register(app.settingsCommand)
        commands.register(app.settingsPageCommands)
        commands.register(Command(
            id: "window.new", title: T("New Window", "Nova janela"), keywords: ["new window", "janela"], category: .file,
            // ⇧⌘N: ⌘N is New Task (plan 29; the mockups).
            defaultShortcut: "cmd+shift+n", action: .run { [weak self] in
                guard let self else { return }
                self.app.newWindow(from: self)
            }))
        commands.register(Command(
            // The sidebar (ADR 0039): ⌘B shows and hides it.
            id: "view.toggle-sidebar", title: T("Show or Hide the Sidebar", "Mostrar ou esconder a barra lateral"),
            keywords: ["sidebar", "explorer", "column", "painel", "coluna", "barra lateral"], category: .view, defaultShortcut: "cmd+b",
            action: .run { [weak self] in self?.toggleInspector() }))
        // The sidebar's two views (ADR 0039, plan 38): Work and Files, by name and by key.
        commands.register(Command(
            id: "sidebar.show-work", title: T("Show Work in the Sidebar", "Mostrar o Trabalho na barra lateral"),
            keywords: ["work", "projects", "tasks", "sidebar", "trabalho", "projetos", "tarefas"], category: .view,
            defaultShortcut: "cmd+shift+1",
            action: .run { [weak self] in self?.workspace?.showWork() }))
        commands.register(Command(
            id: "sidebar.show-files", title: T("Show Files in the Sidebar", "Mostrar os Arquivos na barra lateral"),
            keywords: ["files", "explorer", "tree", "sidebar", "arquivos", "árvore"], category: .view,
            defaultShortcut: "cmd+shift+2",
            action: .run { [weak self] in self?.workspace?.showInspector("files") }))
        // ⌘E swaps the two views (the owner, 2026-11-20: a key beside the others, not only ⇧⌘1/⇧⌘2);
        // from the Memória page or a hidden sidebar it goes to Work.
        commands.register(Command(
            id: "sidebar.switch-view", title: T("Switch Between Work and Files", "Alternar entre Trabalho e Arquivos"),
            keywords: ["work", "files", "switch", "toggle", "sidebar", "trabalho", "arquivos", "alternar"], category: .view,
            defaultShortcut: "cmd+e",
            action: .run { [weak self] in
                guard let self else { return }
                let onWork = self.workspace?.inspectorVisible == true && self.workspace?.sidebar.mode == .work
                _ = self.commands.run(onWork ? "sidebar.show-files" : "sidebar.show-work")
            }))
        // inspector.toggle (⌥⌘I) did the same as ⌘B under another name: one command now (UX audit,
        // 2026-11-18).
        commands.register(PowerCommands.all(app.power))
        commands.register(ThemeCommands.all(store: app.settings.store, palette: palette))
        commands.register(UpdateCommands.all(app.updates))
        commands.register(TerminalCommands.all)
        commands.register(WorkspaceCommands.all(folder, window: { [weak self] in self?.window },
                                                terminalFolder: { [weak self] in self?.tabs?.activeTerminal?.currentDirectory }))
        commands.register(TabCommands.all { [weak self] in self?.tabs })
        commands.register(inspectorTabCommands())
        commands.register(treeCommands(palette: palette))
        commands.register(jumpCommands(palette: palette))
        commands.register(projectPageCommands())
        commands.register(projectsPageCommands())
        commands.register(remoteCommands())
        commands.register(needsQueueCommands())
        commands.register(boardCommands())
        commands.register(moveCommands())
        commands.register(drawerCommands())
        commands.register(SSHCommands.all(palette: palette) { [weak self] alias in self?.connectSSH(alias) })
        commands.register(MachinesCommands.all(palette: palette) { [weak self] machine, ask in self?.connectMachine(machine, askUser: ask) })
        commands.register(DockerCommands.all(palette: palette, actions: dockerActions()))
        commands.register(muteMachineCommand(palette: palette))
        commands.register(ShareCommands.all(palette: palette, actions: shareActions()))
        commands.register(StatusBarCommands.all({ [weak self] in self?.workspace?.statusBar }, palette: palette,
                                                customize: { [weak self] in self?.openCustomize("statusBar") }))
        makeProjects(palette: palette)
        registerWorkColors(palette: palette)
        makeExplorer()
        makeSearch(palette: palette)
        connectPalette(palette)
        let git = SourceControlController(folder: folder.root) { [weak self] id in self?.commands.run(id) ?? false }
        self.git = git
        commands.register(SourceControlCommands.all(git, palette: palette))
        registerReview(palette: palette)
        registerRaces(palette: palette)
        registerRuns(palette: palette)
        registerAutomations(palette: palette)
        commands.register(Command(
            id: "git.show", title: T("Show Git", "Mostrar o Git"), keywords: ["source control", "git", "mudanças", "changes", "commit"],
            category: .view, defaultShortcut: "cmd+shift+g",
            action: .run { [weak self] in
                self?.workspace?.showInspector("changes")
                self?.git?.refresh()
            }))
        commands.register(Command(
            // Opens the sidebar (never closes it, unlike ⌘B); ⇧⌘J stays.
            id: "sidebar.show", title: T("Show the Sidebar", "Mostrar a barra lateral"),
            keywords: ["sidebar", "column", "files", "changes", "tree", "coluna", "lateral", "arquivos", "mudanças", "árvore"], category: .view,
            defaultShortcut: "cmd+shift+j",
            action: .run { [weak self] in self?.workspace?.showTree() }))
        commands.register(Command(
            id: "agents.show-accounts", title: T("Show Agent Accounts", "Mostrar as contas dos agentes"),
            keywords: ["accounts", "usage", "plan", "limit", "contas", "uso", "plano", "limite", "claude"], category: .view,
            // U for usage (the owner asked shortcuts as memorable as ⇧⌘E and ⇧⌘G, 2026-10-22).
            defaultShortcut: "cmd+shift+u",
            // The usage item's card (plan 26 phase E); with the item hidden, the accounts in ⌘K.
            action: .run { [weak self] in
                guard let strip = self?.usageStrip, strip.window != nil, !strip.isHiddenOrHasHiddenAncestor else {
                    _ = self?.commands.run("agents.open-account")
                    return
                }
                strip.openCard()
            }))
        commands.register(Command(
            id: "agents.refresh-usage", title: T("Refresh Agent Usage", "Atualizar o uso dos agentes"),
            keywords: ["usage", "plan", "limit", "refresh", "uso", "plano", "limite", "atualizar"], category: .view,
            action: .run { AgentUsageController.shared.refreshNow() }))
        commands.register(memoryCommands())
        commands.register(memoryOffCommands())
        commands.register(MemoryPageCommands.commands(palette: palette, actions: memoryPageActions()))
        // The project's .ai-memory.toml on a screen, in the project's Settings page (plan 32 D).
        commands.register(Command(
            id: "memory.configure-project", title: T("Configure This Project's Memory", "Configurar a memória deste projeto"),
            keywords: ["memory", "ai-memory.toml", "briefing", "ignore", "memória", "configurar", "projeto"], category: .app,
            action: .run { [weak self] in _ = self?.commands.run("project.show-settings") }))
        commands.register(AgentLaunch.commands(palette: palette, launch: { [weak self] account in self?.launchAgent(for: account) },
                                               continueIn: { [weak self] account in self?.continueInAgent(account) },
                                               customize: { [weak self] in self?.openCustomize("accounts") }))
        commands.register(AgentAccountCommands.commands(palette: palette, actions: accountActions()))
        commands.register(Command(
            id: "agents.show-history", title: T("Show All Sessions (Archive)", "Mostrar todas as sessões (arquivo)"),
            keywords: ["history", "archive", "conversations", "resume", "claude", "histórico", "arquivo", "conversas", "retomar"], category: .view,
            // In the center, as a tab (plan 27 phase C): the sidebar becomes the work's tree.
            action: .run { [weak self] in
                guard let self, let tabs = self.tabs else { return }
                // The tab there already: just shown, no page made for nothing (each one observes the theme).
                tabs.open(tabs.document(identity: AgentHistoryDocument.identity) ?? AgentHistoryDocument(page: self.makeHistoryPage()))
            }))
        commands.register(AgentHistoryCommands.commands(palette: palette, actions: historyActions(), accountName: Self.accountName))
        commands.register(Command(
            id: "agents.show-attention", title: T("Show What Needs You", "Mostrar o que precisa de você"),
            keywords: ["attention", "needs you", "permission", "bell", "atenção", "precisa", "permissão", "sininho"], category: .view,
            action: .run { [weak self] in self?.showAttention("needs") }))
        commands.register(Command(
            id: "agents.show-feed", title: T("Show Agents' Feed", "Mostrar o feed dos agentes"),
            keywords: ["feed", "timeline", "agents", "linha do tempo", "agentes"], category: .view,
            action: .run { [weak self] in self?.showAttention("feed") }))
        commands.register(AgentAttentionCommands.commands(palette: palette))
        commands.register(AgentHibernation.commands(hibernate: { [weak self] in self?.hibernateFocusedAgent() },
                                                    restart: { [weak self] in self?.restartFocusedAgent() }))
        commands.register(WorktreesCommands.commands(palette: palette, actions: worktreesActions()))
        commands.register(Command(
            id: "agents.test-notifications", title: T("Send Test Notifications", "Mandar notificações de teste"),
            keywords: ["notifications", "agents", "test", "notificações", "teste", "avisos"], category: .view,
            action: .run { [weak self] in self?.sendTestNotifications() }))
        commands.register(Command(
            id: "git.show-history", title: T("Show Git History", "Mostrar o histórico do Git"),
            keywords: ["history", "log", "commits", "histórico", "inspector", "painel"], category: .view,
            // L for log, as in git log.
            defaultShortcut: "cmd+shift+l",
            // The graph is a page now (ADR 0039): it left the sidebar.
            action: .run { [weak self] in _ = self?.commands.run("git.history-in-tab") }))
        commands.register(Command(
            id: "history.show-in-tab", title: T("Show Commit Details in a Tab", "Mostrar o commit numa aba"),
            keywords: ["commit", "details", "message", "detalhes", "mensagem", "history", "histórico"], category: .view,
            action: .run { [weak self] in
                guard let history = self?.tabs?.activeDocument as? HistoryDocument, let sha = history.selectedSha else { return }
                self?.opener?.openHistory(history.root, beside: false, selecting: sha)
            },
            unavailableReason: { [weak self] in
                (self?.tabs?.activeDocument as? HistoryDocument)?.selectedSha == nil
                    ? T("Pick a commit in the Git Graph", "Escolha um commit no grafo do git") : nil
            }))
        commands.register(HistoryCommands.all(
            open: { [weak self] beside in if let root = self?.git?.repositoryRoot { self?.opener?.openHistory(root, beside: beside) } },
            repository: { [weak self] in self?.git?.repositoryRoot },
            active: { [weak self] in self?.tabs?.activeDocument as? HistoryDocument }))
        commands.register(withMemoryReindex(EditorCommands.all { [weak self] in self?.tabs?.activeDocument as? EditorDocument }))
        commands.register(MediaCommands.all { [weak self] in self?.tabs?.activeDocument as? MediaDocument })
        // preview.open also takes url= from the agent (docs/adr/0024-agent-tools.md).
        commands.register(PreviewCommands.all(open: { [weak self] url, beside in self?.openPreview(url, beside: beside) },
                                              active: { [weak self] in self?.tabs?.activeDocument as? PreviewDocument }).map { command in
            command.id == "preview.open" ? command.accepting("url=<address>") { [weak self] in self?.agentOpenPreview($0) ?? .failed("the window is gone") } : command
        })
        commands.register(AgentToolsCommands.commands(agentToolsActions()))
        commands.register(ComputerUseCommands.all(toggle: { [weak self] in self?.settings.store.update { $0.computerUse.enabled.toggle() } },
                                                  openPermissions: { [weak self] in self?.app.openComputerUsePermissions() }))
        commands.register(PreviewAgentCommands.all(tab: { [weak self] in self?.agentPreview($0) },
                                                   open: { [weak self] in self?.openAgentPreview($0) },
                                                   enabled: { [weak self] in self?.settings.store.settings.agentTools.browser ?? false },
                                                   active: { [weak self] in self?.tabs?.activeDocument as? PreviewDocument }))
        makeMarkdown(palette: palette)
        connectFolder()
    }

    /// The tree of the workspace folder; its commands act on the focused
    /// terminal through the tabs, and hidden files are a saved preference.
    private func makeExplorer() {
        let explorer = ExplorerController(root: folder.root) { [weak self] id in self?.commands.run(id) ?? false }
        explorer.openInTerminal = { [weak self] path in self?.takeTerminal(to: path) }
        explorer.onShowHiddenChange = { [weak self] show in self?.settings.store.update { $0.explorer.showHidden = show } }
        commands.register(ExplorerCommands.all(explorer))
        self.explorer = explorer
    }

    /// "Abrir no terminal" and a double click on a folder: the focused
    /// terminal goes there; one running a program (an agent, a server) or
    /// a document in focus gets a new terminal tab there instead, since
    /// `cd` would be typed into the program (docs/spec/explorer.md).
    private func takeTerminal(to path: String) {
        guard let tabs else { return }
        if let terminal = tabs.activeTerminal, !terminal.hasForegroundProcess {
            terminal.changeDirectory(to: path)
        } else {
            tabs.newTab(cwd: path)
        }
    }

    /// ⌘P and ⌘⇧F over the workspace folder; the chosen file opens in a tab.
    private func makeSearch(palette: CommandPaletteController) {
        let search = SearchController(root: folder.root, showHidden: true) { [weak self] path, line, beside in
            self?.opener?.open(path, line: line, beside: beside)
        }
        commands.register(SearchCommands.all(search, palette: palette))
        self.search = search
    }

    private func makeMarkdown(palette: CommandPaletteController) {
        let markdown = MarkdownController(root: folder.root, findFiles: { [weak self] in self?.search?.findFiles($0) ?? [] },
                                          open: { [weak self] path, line in self?.opener?.open(path, line: line) })
        self.markdown = markdown
        markdown.runCommand = { [weak self] id in self?.commands.run(id) ?? false }
        commands.register(MarkdownCommands.all(markdown, palette: palette) { [weak self] in
            self?.tabs?.activeDocument as? EditorDocument
        })
    }

    /// The workspace folder reaches the explorer, the search, markdown and
    /// git together.
    private func connectFolder() {
        folder.onChange = { [weak self] root in
            guard let self else { return }
            self.explorer?.setRoot(root)
            self.showPanelFolder(root)
            self.search?.setRoot(root, showHidden: self.explorer?.showHidden ?? true)
            self.markdown?.setRoot(root)
            self.git?.setFolder(root)
            self.projects?.scheduleSave()
            self.showLocation(root)
        }
    }

    /// "project › task" in the title bar: a task's worktree (`<repo>.worktrees/<branch>`, plan 19)
    /// names its repository and the task; any other folder is the project alone.
    func showLocation(_ root: String) {
        // The bar is the same with a page open (plan 34 A, the owner 2026-11-18): the "+" stays,
        // and a page says where it is inside itself, not in the bar.
        workspace?.titleBar.setNewTabHidden(false)
        if tabs?.showsPage == true {
            showProject(branch: lastBranch)
            window.title = [tabs?.activeDocument?.title, "Cadex"].compactMap { $0 }.joined(separator: " — ")
            return refreshTitleAccount()
        }
        let (project, task) = TitleBarView.location(of: root)
        // Where you are, in words, where macOS shows it (Mission Control, ⌘`, the Window menu): the
        // project by the name the owner gave, and the task (UX audit, 2026-11-18).
        let named = projects?.projects.first { $0.folder == projects?.activeFolder }?.name ?? project
        window.title = [[named, task].compactMap { $0 }.joined(separator: " › "), "Cadex"].joined(separator: " — ")
        showProject(branch: lastBranch)
        refreshTitleAccount()
    }

    /// The status bar follows the focused terminal's folder, and its folder
    /// menu takes that terminal there (docs/spec/status-bar.md).
    func connectStatusBar(_ bar: StatusBarView, to tabs: TabsController) {
        tabs.onActiveChange = { [weak self, weak tabs, weak bar] in
            let terminal = tabs?.activeTerminal
            // The title bar's account follows the focused agent (the owner, 2026-11-18).
            self?.refreshTitleAccount()
            // A read that fails for a moment keeps the last folder: the
            // trail emptied and came back, moving the whole bar (2026-10-22).
            if let folder = terminal?.currentDirectory { bar?.path = folder }
            bar?.canNavigate = terminal?.hasForegroundProcess == false
            self?.terminalFolderMoved(terminal?.currentDirectory)
            if let self { self.showLocation(self.folder.root) }
            self?.drawRail()
            self?.refreshWorkColor()
            self?.countTerminals()
            self?.showFocusedAccount()
            self?.forgetFocusedAgentNotification()
            self?.showDockerContext()
            // Ports are read again on a tab or pane switch, only while the item shows.
            if let self, let label = self.portsLabel, label.window != nil { self.readPorts(into: label) }
        }
    }
}
