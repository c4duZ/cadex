import AppKit
import Agents
import Inspector
import Projects
import Sidebar
import Strings
import StateGlyph
import Themes

extension WindowSession {
    /// The sidebar (docs/adr/0039-sidebar-with-work-and-files.md; plan 38 phase B): the Work list
    /// from what is open now; a project's click goes to its last place, a place's to its tabs; the
    /// caret folds; the right click is the project's menu (the rail's, plan 36).
    func makeSidebar() -> WorkSidebarView {
        let sidebar = WorkSidebarView { [weak self] id in _ = self?.commands.run(id) }
        sidebar.onPickProject = { [weak self] folder in self?.pickProject(folder) }
        sidebar.onPickPlace = { [weak self] folder in self?.pickPlace(folder) }
        sidebar.onToggle = { [weak self] folder in self?.toggleProject(folder) }
        sidebar.menuFor = { [weak self] folder in self?.railMenu(folder) ?? [] }
        sidebar.menuForPlace = { [weak self] folder in self?.treeMenu(task: folder) ?? [] }
        sidebar.onPickRequest = { [weak self] id in self?.goToRequest(id) }
        sidebar.onPickRecent = { [weak self] folder in self?.homeOpen(folder) }
        sidebar.onDropImage = { [weak self] folder, url in self?.dropProjectImage(folder, url) }
        sidebar.onShowChanges = { [weak self] in _ = self?.commands.run("git.show") }
        // Dragged: the order kept in projects.json, as the rail's (plan 36 E); pinned does not change.
        sidebar.onMove = { [weak self] folder, order in
            guard let self, let projects = self.projects else { return }
            projects.arrange(order, moved: folder, pinned: projects.isPinned(folder))
            self.drawRail()
        }
        sidebar.onMode = { [weak self] mode in
            _ = self?.commands.run(mode == .work ? "sidebar.show-work" : "sidebar.show-files")
        }
        return sidebar
    }

    /// The projects as the sidebar lists them: the pinned first in their order, then the open ones
    /// not pinned; the home folder's terminals are no project (plan 36). Each with main and its
    /// tasks, their states and terminals, and how many of its agents wait on you.
    func sidebarModel() -> [WorkProject] {
        let all = (projects?.projects ?? []).filter { !Self.isLoose($0.folder) }
        let ordered = all.filter(\.pinned) + all.filter { !$0.pinned }
        let tree = Dictionary(treeModel().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // The queue's requests by project too: the amber count and the queue never disagree.
        let asking = Dictionary(grouping: AgentAttention.shared.cards, by: \.project).mapValues(\.count)
        // The home folder's terminals: no project, but a line at the end while any is open, so going
        // into a project never loses them (the owner, 2026-11-20: "se eu entrar em projeto, eu vou
        // perder ele").
        let loose = (projects?.projects ?? []).first { Self.isLoose($0.folder) && !$0.tabs.allTerminals.isEmpty }.map { project in
            let terminals = project.tabs.allTerminals
            let states = terminals.compactMap { Self.treeRow($0).state }
            return WorkProject(id: project.folder, name: T("No project", "Sem projeto"), emoji: "~", state: Self.summary(states),
                               terminals: terminals.count, waiting: states.filter { $0 == .needs }.count, pinned: false)
        }
        return ordered.map { project in
            let terminals = project.tabs.allTerminals
            let states = terminals.compactMap { Self.treeRow($0).state }
            let tint = Self.workTint(project.color)
            let node = tree[project.folder]
            let ownStates = node?.terminals.compactMap(\.state) ?? []
            var places = [WorkPlace(id: project.folder, name: node.map { $0.branch.isEmpty ? "main" : $0.branch } ?? "main", isMain: true,
                                    state: Self.summary(ownStates), terminals: node?.terminals.count ?? 0)]
            places += (node?.tasks ?? []).map { task in
                WorkPlace(id: task.id, name: task.name, state: task.state, terminals: task.terminals.count)
            }
            return WorkProject(id: project.folder, name: project.name, tint: tint, image: projects?.imageURL(project.image)?.path,
                               emoji: project.emoji, state: Self.summary(states), terminals: terminals.count,
                               waiting: max(states.filter { $0 == .needs }.count, asking[project.name] ?? 0), expanded: isExpanded(project.folder),
                               places: places, pinned: project.pinned)
        } + (loose.map { [$0] } ?? [])
    }

    /// The narrow window's strip (plan 38 G): the projects' squares, the requests' box, Files and the
    /// board; a square's click goes to the project, the right click is its menu, dragging reorders.
    func makeStrip() -> RailView {
        let rail = RailView { [weak self] id in _ = self?.commands.run(id) }
        rail.onPick = { [weak self] folder in self?.pickProject(folder) }
        rail.menuFor = { [weak self] folder in self?.railMenu(folder) ?? [] }
        rail.onDropImage = { [weak self] folder, url in self?.dropProjectImage(folder, url) }
        rail.onMove = { [weak self] folder, order, pinned in
            self?.projects?.arrange(order, moved: folder, pinned: pinned)
            self?.drawRail()
        }
        return rail
    }

    /// The strip's squares, from the sidebar's model.
    func stripModel(_ projects: [WorkProject]) -> [RailProject] {
        projects.map { RailProject(id: $0.id, name: $0.name, tint: $0.tint, state: $0.waiting > 0 ? .needs : $0.state,
                                   open: $0.terminals > 0, image: $0.image, emoji: $0.emoji, pinned: $0.pinned) }
    }

    /// Redrawn with the tree (TreeWiring.drawTree), from what is open now; the place lit is where
    /// the top bar's tabs are: a task's, or the project's main.
    func drawRail() {
        guard let sidebar = workspace?.sidebar else { return }
        let folder = projects?.activeFolder.flatMap { Self.isLoose($0) ? nil : $0 }
        let group = tabs?.currentGroup
        let place = folder.map { group.flatMap { $0.isEmpty ? nil : $0 } ?? $0 }
        let model = sidebarModel()
        if model.isEmpty { drawNothingOpen(sidebar) } else { sidebar.show(model, place: place) }
        workspace?.statusBar.only = model.isEmpty ? Self.nothingOpenItems : nil
        sidebar.remoteShown = hasRemote
        if let strip = workspace?.rail {
            strip.show(stripModel(model), chosen: folder)
            strip.requests = AgentAttention.shared.cards.count
        }
        showPlace()
    }

    /// Folded or unfolded, as the owner left it (projects.json, plan 38); the shown one unfolded
    /// until the owner folds it.
    func isExpanded(_ folder: String) -> Bool {
        if let choice = projects?.projects.first(where: { $0.folder == folder })?.expanded { return choice }
        return folder == projects?.activeFolder
    }

    func toggleProject(_ folder: String) {
        projects?.setExpanded(!isExpanded(folder), for: folder)
        drawRail()
    }

    /// A place clicked: its project shown and its tabs in the top bar (a task's, or the project's own).
    func pickPlace(_ folder: String) {
        if let project = projects?.projects.first(where: { $0.folder == folder }) {
            pickProject(project.folder)
            _ = commands.run("project.show-terminals")
            return
        }
        pickInTree(.task(folder))
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
