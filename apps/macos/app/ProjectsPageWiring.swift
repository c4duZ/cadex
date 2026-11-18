import Agents
import AppKit
import CommandPalette
import Memory
import Projects
import StateGlyph
import Strings
import Worktrees

/// The Projects page (plan 34 B): project.show-all, from the sidebar's foot and ⌘K; a card per
/// project with its tasks (the tree's), sessions (the history's, read while a page shows) and
/// memories (its wiki, counted off the main thread), and what goes on (a live agent working or
/// waiting, else the last session). A click opens the project's page; Add project is project.new.
extension WindowSession {
    func projectsPageCommands() -> [Command] {
        [Command(id: "project.show-all", title: T("Show Projects", "Mostrar os projetos"),
                 keywords: ["projects", "list", "all", "memory", "sessions", "projetos", "lista", "todos", "memória", "sessões"],
                 category: .view, action: .run { [weak self] in self?.openProjectsPage() })]
    }

    func openProjectsPage() {
        if let open = tabs?.document(identity: ProjectsListDocument.identity) { return tabs?.open(open) ?? () }
        tabs?.open(makeProjectsPage())
        watchHistoryForPages()
    }

    func makeProjectsPage() -> ProjectsListDocument {
        var actions = ProjectsListActions()
        actions.open = { [weak self] folder in self?.openProjectPage(folder) }
        actions.add = { [weak self] in _ = self?.commands.run("project.new") }
        actions.load = { [weak self] show in self?.loadProjectCards(show) }
        return ProjectsListDocument(actions: actions)
    }

    /// The history is read while a page that lists sessions shows (the Projects page, a project's).
    func watchHistoryForPages() {
        guard projectPageHistory == nil else { return }
        projectPageHistory = AgentHistoryController.shared.watch { [weak self] in
            (self?.tabs?.activeDocument as? ProjectPageDocument)?.reload()
            (self?.tabs?.activeDocument as? ProjectsListDocument)?.reload()
        }
    }

    private func loadProjectCards(_ show: @escaping @MainActor ([ProjectCard]) -> Void) {
        let open = projects?.projects.map { ($0.folder, $0.name) } ?? []
        let tree = treeModel()
        let history = AgentHistoryController.shared.entries
        let live = AgentsController.shared.sessions
        let home = NSHomeDirectory()
        let wikis = open.map { MemoryPageState.wikiDir(overview: nil, root: $0.0, folder: MemoryKit.folder()) }
        DispatchQueue.global(qos: .userInitiated).async {
            let memories = wikis.map { wiki in wiki.flatMap { FileManager.default.fileExists(atPath: $0) ? MemoryWiki.tree($0).allPages.count : nil } ?? 0 }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let now = Date()
                    show(open.enumerated().map { index, project in
                        let (folder, name) = project
                        let mine = history.filter { Self.belongs($0.cwd, to: folder) }
                        let here = live.filter { Self.belongs($0.cwd, to: folder) }
                        let branch = tree.first { $0.id == folder }?.branch ?? ""
                        let path = folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
                        let (status, state) = Self.projectStatus(live: here, last: mine.compactMap(\.updated).max(), now: now)
                        return ProjectCard(folder: folder, name: name, place: [String(path), branch].filter { !$0.isEmpty }.joined(separator: " · "),
                                           tasks: tree.first { $0.id == folder }?.tasks.count ?? 0, sessions: mine.count,
                                           memories: memories[index], status: status, state: state)
                    })
                }
            }
        }
    }

    /// "1 waiting for you", "agent working · 8 min", "last session yesterday", "no session yet".
    static func projectStatus(live: [AgentSession], last: Date?, now: Date) -> (String, GlyphState?) {
        let waiting = live.filter { $0.waitingFor != nil }.count
        if waiting > 0 { return (waiting == 1 ? T("1 waiting for you", "1 esperando você") : T("\(waiting) waiting for you", "\(waiting) esperando você"), .needs) }
        if let working = live.first(where: { $0.status == .working }) {
            return (T("agent working · ", "agente trabalhando · ") + ProjectPageWords.when(working.since, now: now), .working)
        }
        guard let last else { return (T("no session yet", "nenhuma sessão ainda"), nil) }
        return (T("last session ", "última sessão ") + ProjectPageWords.when(last, now: now), nil)
    }
}
