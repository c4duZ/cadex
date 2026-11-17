import AppKit
import Worktrees
import Themes
import Customize
import Explorer
import GitHistory
import Memory
import Icons
import Settings
import Shortcuts
import Sidebar
import SourceControl
import Strings

/// The sidebar's catalog in this window: each page's view comes from its
/// feature, each icon runs a command (docs/spec/sidebar.md). Tasks, Agents,
/// History and Accounts are pages (Agents and Accounts apart, each with its
/// icon and so its own shortcut: the owner, 2026-10-21). Files, Git, Git
/// History and Memory went to the right panel (plan 26 phase C,
/// InspectorWiring.swift); the sidebar becomes the work's tree in plan 27.
extension WindowSession {
    func makeSidebar() -> SidebarView {
        // Each page's header: up to three buttons, the rest under "⋯"
        // (docs/spec/sidebar.md, "Cabeçalho da página").
        let catalog = [
            item("agents", .sparkle, T("Agents", "Agentes"), "agents.show", .page(makeAgentsPage("sessions"))),
            item("agent-history", .clipboardText, T("History", "Histórico"), "agents.show-history", .page(makeHistoryPage()), actions: [
                SidebarAction("agents.resume-session", .terminalWindow, T("Resume a Conversation", "Retomar uma conversa")),
            ]),
            item("tasks", .stack, T("Tasks", "Tarefas"), "worktrees.show", .page(makeTasksPage()), actions: [
                SidebarAction("worktrees.new-task", .plus, T("New Task", "Nova tarefa")),
            ], more: [
                SidebarAction("worktrees.edit-setup-hooks", .slidersHorizontal, T("Edit Setup Hooks", "Editar os hooks de preparo")),
            ]),
            item("accounts", .gauge, T("Accounts", "Contas"), "agents.show-accounts", .page(makeAgentsPage("accounts")), actions: [
                SidebarAction("agents.refresh-usage", .arrowsClockwise, T("Refresh Usage", "Atualizar o uso")),
                SidebarAction("agents.customize-accounts", .slidersHorizontal, T("Customize Accounts", "Personalizar as contas")),
            ]),
        ]
        let sidebar = SidebarView(catalog: catalog) { [weak self] id in _ = self?.commands.run(id) }
        sidebar.onItemsChange = { [weak self] ids in self?.settings.store.update { $0.sidebar.items = ids } }
        sidebar.onCustomize = { [weak self] in self?.openCustomize("sidebar") }
        applySidebar(settings.store.settings.sidebar, to: sidebar)
        return sidebar
    }

    static let movedToInspector: Set<String> = ["files", "git", "history", "memory"]

    /// sidebar.items from settings, in this window.
    func applySidebar(_ prefs: Settings.Sidebar) {
        guard let sidebar = workspace?.sidebar else { return }
        applySidebar(prefs, to: sidebar)
    }

    private func applySidebar(_ prefs: Settings.Sidebar, to sidebar: SidebarView) {
        // Ids of pages that moved to the right panel, saved before plan 26: dropped without a
        // warning (the panel has them). Here and not in SidebarLayout.retired: the sidebar's own
        // tests still use these ids as plain pages, and the bar itself goes in plan 27.
        let items = prefs.items.filter { !Self.movedToInspector.contains($0) }
        if items != sidebar.items {
            for problem in sidebar.setItems(items) { NSLog("Cadex settings: %@", problem) }
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

    private func item(_ id: String, _ icon: Icon, _ title: String, _ command: String, _ kind: SidebarItem.Kind,
                      actions: [SidebarAction] = [], more: [SidebarAction] = []) -> SidebarItem {
        let shortcut = app.keymapLabel(command)
            ?? commands.command(command)?.defaultShortcut.flatMap { KeyCombo($0)?.label }
        return SidebarItem(id: id, icon: icon, title: title, command: command, shortcut: shortcut, kind: kind,
                           actions: actions, more: more)
    }
}
