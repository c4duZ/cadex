import AppKit
import CommandPalette
import Editor
import Explorer
import GitHistory
import Markdown
import MediaPreview
import Power
import Preview
import Search
import Settings
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
        self.palette = palette
        commands.register(palette.openCommand)
        commands.register(StandardCommands.all)
        commands.register(app.settingsCommand)
        commands.register(app.settingsPageCommands)
        commands.register(Command(
            id: "window.new", title: T("New Window", "Nova janela"), keywords: ["new window", "janela"], category: .file,
            defaultShortcut: "cmd+n", action: .run { [weak self] in
                guard let self else { return }
                self.app.newWindow(from: self)
            }))
        commands.register(Command(
            id: "view.toggle-sidebar", title: T("Show or Hide Sidebar", "Mostrar ou esconder o painel lateral"),
            keywords: ["sidebar", "explorer", "painel"], category: .view, defaultShortcut: "cmd+b",
            action: .run { [weak self] in self?.workspace?.toggleSidebar() }))
        commands.register(PowerCommands.all(app.power))
        commands.register(ThemeCommands.all(store: app.settings.store, palette: palette))
        commands.register(UpdateCommands.all(app.updates))
        commands.register(TerminalCommands.all)
        commands.register(WorkspaceCommands.all(folder, window: { [weak self] in self?.window },
                                                terminalFolder: { [weak self] in self?.tabs?.activeTerminal?.currentDirectory }))
        commands.register(TabCommands.all { [weak self] in self?.tabs })
        commands.register(SidebarCommands.all({ [weak self] in self?.workspace?.sidebar }, palette: palette))
        commands.register(StatusBarCommands.all({ [weak self] in self?.workspace?.statusBar }, palette: palette,
                                                customize: { [weak self] in self?.openCustomize("statusBar") }))
        makeSpaces(palette: palette)
        registerWorkColors(palette: palette)
        makeExplorer()
        makeSearch(palette: palette)
        connectPalette(palette)
        let git = SourceControlController(folder: folder.root) { [weak self] id in self?.commands.run(id) ?? false }
        self.git = git
        commands.register(SourceControlCommands.all(git, palette: palette) { [weak self] in
            self?.tabs?.activeDocument as? DiffDocument
        })
        commands.register(Command(
            id: "git.show", title: T("Show Git", "Mostrar o Git"), keywords: ["source control", "git", "mudanças", "changes", "commit"],
            category: .view, defaultShortcut: "cmd+shift+g",
            action: .run { [weak self] in
                self?.workspace?.showSidebar("git")
                self?.git?.refresh()
            }))
        commands.register(Command(
            id: "git.show-history", title: T("Show Git History in Sidebar", "Mostrar o histórico do Git no painel lateral"),
            keywords: ["history", "log", "commits", "histórico", "sidebar", "painel"], category: .view,
            action: .run { [weak self] in self?.workspace?.showSidebar("history") }))
        commands.register(Command(
            id: "history.show-in-tab", title: T("Show Commit Details in a Tab", "Mostrar o commit numa aba"),
            keywords: ["commit", "details", "message", "detalhes", "mensagem", "history", "histórico"], category: .view,
            action: .run { [weak self] in
                guard let history = self?.sidebarHistory, let sha = history.selectedSha else { return }
                self?.opener?.openHistory(history.root, beside: false, selecting: sha)
            },
            unavailableReason: { [weak self] in
                self?.sidebarHistory?.selectedSha == nil ? T("Pick a commit in the sidebar's Git History", "Escolha um commit no histórico do painel lateral") : nil
            }))
        commands.register(HistoryCommands.all(
            open: { [weak self] beside in if let root = self?.git?.repositoryRoot { self?.opener?.openHistory(root, beside: beside) } },
            repository: { [weak self] in self?.git?.repositoryRoot },
            // The sidebar's history when the tab in front is not one: its
            // right-click menu runs these too.
            active: { [weak self] in self?.tabs?.activeDocument as? HistoryDocument ?? self?.sidebarHistory }))
        commands.register(EditorCommands.all { [weak self] in self?.tabs?.activeDocument as? EditorDocument })
        commands.register(MediaCommands.all { [weak self] in self?.tabs?.activeDocument as? MediaDocument })
        commands.register(PreviewCommands.all(open: { [weak self] url, beside in self?.openPreview(url, beside: beside) },
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
            self.workspace?.sidebar.setTitle(Self.folderName(root), for: "files")
            self.search?.setRoot(root, showHidden: self.explorer?.showHidden ?? true)
            self.markdown?.setRoot(root)
            self.git?.setFolder(root)
            self.sidebarFolderChanged()
            self.spaces?.scheduleSave()
        }
    }

    /// The status bar follows the focused terminal's folder, and its folder
    /// menu takes that terminal there (docs/spec/status-bar.md).
    func connectStatusBar(_ bar: StatusBarView, to tabs: TabsController) {
        tabs.onActiveChange = { [weak self, weak tabs, weak bar] in
            let terminal = tabs?.activeTerminal
            bar?.path = terminal?.currentDirectory
            bar?.canNavigate = terminal?.hasForegroundProcess == false
            self?.terminalFolderMoved(terminal?.currentDirectory)
            self?.refreshWorkColor()
            self?.countTerminals()
        }
    }
}
