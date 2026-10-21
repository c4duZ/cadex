import AppKit
import Explorer
import Icons
import Settings
import Shortcuts
import Sidebar
import SourceControl
import Strings

/// The sidebar's catalog in this window: each page's view comes from its
/// feature, each icon runs a command (docs/spec/sidebar.md). Files and Git
/// are pages; Search, History, Preview and Spaces only run their command.
extension WindowSession {
    func makeSidebar(explorer: ExplorerController, git: SourceControlController) -> SidebarView {
        let catalog = [
            item("files", .files, T("Files", "Arquivos"), "explorer.focus", .page(explorer.view)),
            item("search", .magnifyingGlass, T("Search", "Busca"), "search.content", .action),
            item("git", .gitBranch, "Git", "git.show", .page(git.view)),
            item("history", .clockCounterClockwise, T("Git History", "Histórico do Git"), "git.history", .action),
            item("preview", .globe, T("Web Preview", "Preview web"), "preview.open", .action),
            item("spaces", .stack, "Spaces", "space.switch", .action),
        ]
        let sidebar = SidebarView(catalog: catalog) { [weak self] id in _ = self?.commands.run(id) }
        sidebar.onItemsChange = { [weak self] ids in self?.settings.store.update { $0.sidebar.items = ids } }
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
