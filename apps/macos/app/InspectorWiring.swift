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
        // Files and Changes, the sidebar's Files view (ADR 0039): Sessions, Memory and the graph moved
        // to the project's page.
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
        ]
        let shortcut = app.keymapLabel("view.toggle-sidebar") ?? "⌘B"
        // The pages' icons are the rail's (ADR 0038, revised 2026-11-18): none on top of the column.
        let inspector = InspectorView(tabs: tabs, shortcut: shortcut, tabsOnTop: false, scopeOnTop: true) { [weak self] id in _ = self?.commands.run(id) }
        inspector.onShow = { [weak self] id in
            self?.showChangesLine()
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

    /// ⌃⌘1 and ⌃⌘2: Files and Changes, the sidebar's Files view (plan 26 phase E; Sessions, Memory
    /// and the graph, ⌃⌘3 to ⌃⌘5, left with plan 38).
    func inspectorTabCommands() -> [Command] {
        (1...2).map { n in
            Command(id: "inspector.tab-\(n)", title: T(n == 1 ? "Show Files in the Sidebar" : "Show Changes in the Sidebar", n == 1 ? "Mostrar Arquivos na barra lateral" : "Mostrar Mudanças na barra lateral"),
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
        workspace.setSidebarByOwner(visible: prefs.visible, launching: true)
        // A window that opens narrow keeps its terminals' room (ADR 0038).
        workspace.fitColumn(to: workspace.bounds.width)
        // Closed: the tab is only picked, so nothing reads behind a hidden panel.
        if workspace.inspector.tab != prefs.tab { workspace.inspector.show(prefs.tab, announce: prefs.visible) }
    }

    /// view.toggle-sidebar (⌘B, the title bar's button): saved, so it comes back on reopen.
    func toggleInspector() {
        guard let workspace else { return }
        workspace.setSidebarByOwner(visible: !workspace.inspectorVisible)
        let visible = workspace.inspectorVisible
        settings.store.update { $0.inspector.visible = visible }
    }

    /// The scope row of Files: the folder's name, the whole path in the tip; and Files' head in words.
    func showPanelFolder(_ root: String) {
        showFilesHead(root)
        workspace?.inspector.setScope(InspectorScope(Self.folderName(root), tip: root), for: "files")
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

    /// Files' head in words (plan 38 phase D): a task says whose and against what ("task of cadex ·
    /// against main"), a project's main its branch, a folder outside git where it is.
    func showFilesHead(_ root: String) {
        guard let sidebar = workspace?.sidebar else { return }
        let home = NSHomeDirectory()
        let path = root.hasPrefix(home) ? "~" + root.dropFirst(home.count) : root
        // A subfolder (the terminal's, showFilesWhereTerminalIs) is named by the project or task it is in.
        let top = Self.folder(root, isIn: folder.root) ? folder.root : root
        let sub = top == root ? "" : String(root.dropFirst(top.count))
        if let task = WorktreesController.shared.store.task(top) {
            let project = TitleBarView.location(of: top).project
            let base = task.base.isEmpty ? "" : T(" · against \(task.base)", " · contra \(task.base)")
            return sidebar.setFilesHead(title: Self.folderName(top) + sub, detail: T("task of \(project)", "tarefa de \(project)") + base)
        }
        let name = projects?.projects.first { $0.folder == top }?.name ?? Self.folderName(top)
        sidebar.setFilesHead(title: name + sub, detail: String(path))
    }

    /// "N changes · see" at the end of Files, hidden while Changes shows.
    func showChangesLine() {
        guard let workspace else { return }
        workspace.sidebar.setChanges(count: changedFiles, showingChanges: workspace.inspector.tab == "changes")
    }
}
