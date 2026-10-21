import AppKit
import Themes
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
/// feature, each icon runs a command (docs/spec/sidebar.md). Files, Git,
/// Git History, Agents and Accounts are pages (Agents and Accounts apart,
/// each with its icon and so its own shortcut: the owner, 2026-10-21); Search only runs its command (⌘K). Only what
/// shows in the sidebar belongs here: Web Preview and Spaces opened
/// something elsewhere and were taken out (owner, 2026-10-21).
extension WindowSession {
    func makeSidebar(explorer: ExplorerController, git: SourceControlController) -> SidebarView {
        let catalog = [
            item("files", .files, T("Files", "Arquivos"), "explorer.focus", .page(explorer.view)),
            item("search", .magnifyingGlass, T("Search", "Busca"), "search.content", .action),
            item("git", .gitBranch, "Git", "git.show", .page(git.view)),
            item("history", .clockCounterClockwise, T("Git History", "Histórico do Git"), "git.show-history", .page(sidebarHistoryHost)),
            item("agents", .sparkle, T("Agents", "Agentes"), "agents.show", .page(makeAgentsPage("sessions"))),
            item("accounts", .gauge, T("Accounts", "Contas"), "agents.show-accounts", .page(makeAgentsPage("accounts"))),
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
        if prefs.items != sidebar.items {
            for problem in sidebar.setItems(prefs.items) { NSLog("Cadex settings: %@", problem) }
            refreshCustomize()
        }
        updateAgentsDot(shown: sidebar.items.contains("agents"), on: sidebar)
    }

    /// The one Customize window, on a tab (sidebar or statusBar), with this
    /// window's sidebar and status bar; over this window, in full screen too.
    func openCustomize(_ page: String) {
        guard let workspace else { return }
        Self.followThemeInCustomize()
        CustomizeWindow.shared.show(customizePages(workspace), selecting: page, colors: Self.customizeColors(), over: window)
    }

    /// The settings window's colors, from the theme itself: not the window's
    /// accent, which a space's or tab's color replaces (the owner saw blue
    /// switches under Caffeine, 2026-10-21).
    static func customizeColors() -> CustomizeColors {
        let ui = ThemeStore.shared.current.interface
        return CustomizeColors(text: ui.text.nsColor, secondary: ui.secondaryText.nsColor, accent: ui.accent.nsColor,
                               panel: ui.panel.nsColor, box: ui.chrome.color(alpha: 0.6), border: ui.panelBorder.nsColor)
    }

    private static var followsTheme = false

    /// Once for the app: a theme change repaints the open Customize window.
    private static func followThemeInCustomize() {
        guard !followsTheme else { return }
        followsTheme = true
        ThemeStore.shared.observe { _ in CustomizeWindow.shared.recolor(customizeColors()) }
    }

    /// Settings changed while it is open: it shows them.
    func refreshCustomize() {
        guard let workspace, window.isKeyWindow || CustomizeWindow.shared.isKeyWindow else { return }
        CustomizeWindow.shared.refresh(customizePages(workspace))
    }

    private func customizePages(_ workspace: WorkspaceView) -> [CustomizePage] {
        [workspace.sidebar.customizePage, workspace.statusBar.customizePage, accountsPage()]
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

    private func item(_ id: String, _ icon: Icon, _ title: String, _ command: String, _ kind: SidebarItem.Kind,
                      subtabs: [SidebarItem.Subtab] = []) -> SidebarItem {
        let shortcut = app.keymapLabel(command)
            ?? commands.command(command)?.defaultShortcut.flatMap { KeyCombo($0)?.label }
        return SidebarItem(id: id, icon: icon, title: title, command: command, shortcut: shortcut, kind: kind, subtabs: subtabs)
    }
}
