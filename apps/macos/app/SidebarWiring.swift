import AppKit
import Customize
import Explorer
import GitHistory
import Icons
import Settings
import Shortcuts
import Sidebar
import SourceControl
import Strings

/// The sidebar's catalog in this window: each page's view comes from its
/// feature, each icon runs a command (docs/spec/sidebar.md). Files, Git and
/// Git History are pages; Search only runs its command (⌘K). Only what
/// shows in the sidebar belongs here: Web Preview and Spaces opened
/// something elsewhere and were taken out (owner, 2026-10-21).
extension WindowSession {
    func makeSidebar(explorer: ExplorerController, git: SourceControlController) -> SidebarView {
        let catalog = [
            item("files", .files, T("Files", "Arquivos"), "explorer.focus", .page(explorer.view)),
            item("search", .magnifyingGlass, T("Search", "Busca"), "search.content", .action),
            item("git", .gitBranch, "Git", "git.show", .page(git.view)),
            item("history", .clockCounterClockwise, T("Git History", "Histórico do Git"), "git.show-history", .page(sidebarHistoryHost)),
        ]
        let sidebar = SidebarView(catalog: catalog) { [weak self] id in _ = self?.commands.run(id) }
        sidebar.onItemsChange = { [weak self] ids in self?.settings.store.update { $0.sidebar.items = ids } }
        sidebar.onShow = { [weak self] id in if id == "history" { self?.showSidebarHistory() } }
        sidebar.onCustomize = { [weak self] in self?.openCustomize("sidebar") }
        sidebar.setTitle(Self.folderName(folder.root), for: "files")
        applySidebar(settings.store.settings.sidebar, to: sidebar)
        return sidebar
    }

    /// sidebar.items from settings, in this window.
    func applySidebar(_ prefs: Settings.Sidebar) {
        guard let sidebar = workspace?.sidebar else { return }
        applySidebar(prefs, to: sidebar)
    }

    private func applySidebar(_ prefs: Settings.Sidebar, to sidebar: SidebarView) {
        guard prefs.items != sidebar.items else { return }
        for problem in sidebar.setItems(prefs.items) { NSLog("Cadex settings: %@", problem) }
        refreshCustomize()
    }

    /// The one Customize window, on a tab (sidebar or statusBar), with this
    /// window's sidebar and status bar; over this window, in full screen too.
    func openCustomize(_ page: String) {
        guard let workspace else { return }
        CustomizeWindow.shared.show(customizePages(workspace), selecting: page,
                                    colors: workspace.statusBar.style.customize, over: window)
    }

    /// Settings changed while it is open: it shows them.
    func refreshCustomize() {
        guard let workspace, window.isKeyWindow || CustomizeWindow.shared.isKeyWindow else { return }
        CustomizeWindow.shared.refresh(customizePages(workspace))
    }

    private func customizePages(_ workspace: WorkspaceView) -> [CustomizePage] {
        [workspace.sidebar.customizePage, workspace.statusBar.customizePage]
    }

    /// The Git History page: the repository's history, compact, made the
    /// first time the page shows and again when the repository changes.
    /// Outside a repository the page says so. The root comes from git, off
    /// the main thread (source-control's rule).
    func showSidebarHistory() {
        let folder = self.folder.root
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let root = SourceControlController.repositoryRoot(containing: folder)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.folder.root == folder else { return }
                    self.placeSidebarHistory(root)
                }
            }
        }
    }

    private func placeSidebarHistory(_ root: String?) {
        if let current = sidebarHistory, current.root == root { return }
        sidebarHistory?.view.removeFromSuperview()
        sidebarHistory = nil
        sidebarHistoryHost.subviews.forEach { $0.removeFromSuperview() }
        guard let root, let opener else {
            let label = NSTextField(labelWithString: T("Not a Git repository", "Não é um repositório Git"))
            label.textColor = .secondaryLabelColor
            fill(sidebarHistoryHost, with: label, centered: true)
            return
        }
        let history = opener.makeHistory(root)
        history.compact = true
        sidebarHistory = history
        fill(sidebarHistoryHost, with: history.view, centered: false)
    }

    /// The workspace moved: the page follows, if it was ever opened.
    func sidebarFolderChanged() {
        guard sidebarHistory != nil || !sidebarHistoryHost.subviews.isEmpty else { return }
        if workspace?.sidebar.page == "history" { showSidebarHistory() } else {
            sidebarHistory?.view.removeFromSuperview()
            sidebarHistory = nil
            sidebarHistoryHost.subviews.forEach { $0.removeFromSuperview() }
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

    /// The count of changed files on the Git icon, none when clean.
    func showGitBadge(_ marks: [String: Character]) {
        workspace?.sidebar.setBadge(marks.isEmpty ? nil : "\(marks.count)", for: "git")
    }

    static func folderName(_ path: String) -> String { (path as NSString).lastPathComponent }

    private func item(_ id: String, _ icon: Icon, _ title: String, _ command: String, _ kind: SidebarItem.Kind) -> SidebarItem {
        let shortcut = app.keymapLabel(command)
            ?? commands.command(command)?.defaultShortcut.flatMap { KeyCombo($0)?.label }
        return SidebarItem(id: id, icon: icon, title: title, command: command, shortcut: shortcut, kind: kind)
    }
}
