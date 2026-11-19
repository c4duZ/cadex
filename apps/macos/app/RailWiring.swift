import AppKit
import Inspector
import Projects
import Sidebar
import StateGlyph
import Themes

/// The rail in this window (docs/adr/0038-rail-and-side-column.md; plan 36 phase A): the projects
/// with their state, the chosen one ringed; a click shows its terminals in the tabs and the side
/// column on it. Redrawn with the tree (TreeWiring.drawTree), from what is open now.
extension WindowSession {
    func makeRail() -> RailView {
        let rail = RailView { [weak self] id in _ = self?.commands.run(id) }
        rail.onPick = { [weak self] folder in self?.pickProject(folder) }
        rail.menuFor = { [weak self] folder in self?.railMenu(folder) ?? [] }
        rail.onDropImage = { [weak self] folder, url in self?.dropProjectImage(folder, url) }
        // Dragged (plan 36 phase E): the projects' order and pinned kept in projects.json, the pages'
        // in the settings (inspector.order), which the inspector.tab-N commands follow too.
        rail.onMove = { [weak self] folder, order, pinned in
            self?.projects?.arrange(order, moved: folder, pinned: pinned)
            self?.drawRail()
        }
        rail.onMovePages = { [weak self] ids in
            self?.workspace?.inspector.reorder(ids)
            self?.settings.store.update { $0.inspector.order = ids }
        }
        return rail
    }

    /// The side column's pages as the rail shows them: their icons, under the projects.
    func railPages(_ inspector: InspectorView) -> [RailPage] {
        inspector.pages.map { RailPage(id: $0.id, title: $0.title, icon: $0.icon, command: $0.command) }
    }

    /// The projects as the rail draws them.
    func railModel() -> [RailProject] {
        let theme = ThemeStore.shared.current
        // The pinned first, in their order; then the open ones that are not pinned. The home
        // folder's terminals are no project (plan 36: tabs of no project, no tile lit).
        let all = (projects?.projects ?? []).filter { !Self.isLoose($0.folder) }
        let ordered = all.filter(\.pinned) + all.filter { !$0.pinned }
        return ordered.map { project in
            let terminals = project.tabs.allTerminals
            let states = terminals.compactMap { Self.treeRow($0).state }
            let tint = project.color.flatMap(WorkColor.init(rawValue:)).map { color -> [Double] in
                let value = color.rgb(in: theme).value
                return [Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255]
            }
            return RailProject(id: project.folder, name: project.name, tint: tint, state: Self.summary(states), open: !terminals.isEmpty,
                               image: projects?.imageURL(project.image)?.path, emoji: project.emoji, pinned: project.pinned)
        }
    }

    func drawRail() {
        guard let rail = workspace?.rail else { return }
        rail.show(railModel(), chosen: projects?.activeFolder.flatMap { Self.isLoose($0) ? nil : $0 })
        rail.remoteShown = hasRemote
        let page = tabs?.showsPage == true ? tabs?.activeDocument?.identity : nil
        rail.footLit = page == ProjectsListDocument.identity ? .projects
            : page?.hasPrefix("automation") == true ? .automations : nil
    }

    /// The terminals opened in the home folder: tabs of no project (ADR 0038, decided 2026-11-18).
    static func isLoose(_ folder: String) -> Bool {
        folder == NSHomeDirectory() || folder == URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path
    }

    /// A tile clicked: that project's tabs and column; one without a terminal gets one in its folder.
    func pickProject(_ folder: String) {
        guard let projects, let index = projects.projects.firstIndex(where: { $0.folder == folder }) else { return }
        projects.select(index)
        let tabs = projects.projects[index].tabs
        if tabs.allTerminals.isEmpty { tabs.newTab(cwd: folder) }
        // A page in the center (Projects, Automations) gives way to the terminals.
        if tabs.showsPage { tabs.leavePage() }
        refreshTree()
    }
}
