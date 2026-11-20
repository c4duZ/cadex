import AppKit
import CommandPalette
import Memory
import Sidebar
import Strings

/// The Memória page (plans 40 C and D; docs/plans/40-memory-panel.md): memory.show-panel opens it
/// in the center like Automations and swaps the sidebar for its sections (Memória in the sidebar's
/// foot, ⌘K, a section's line with section=, any click inside with project= and the screen);
/// memory.panel-back and memory.panel-forward walk the places seen (⌘[ and ⌘] in the page);
/// memory.open-in-cadex goes to a session's terminal, or the Cadex project with a memory
/// project's folder. The data comes from the engine's panel routes through
/// `cadex memory-agent panel --path P` (MemoryWiring.runAgentData).
extension WindowSession {
    func memoryPanelCommands() -> [Command] {
        [Command(id: "memory.show-panel", title: T("Show the Memory Panel", "Mostrar o painel da memória"),
                 keywords: ["memory", "panel", "projects", "inbox", "workstreams", "graph", "health", "memória", "painel", "projetos",
                            "caixa de entrada", "grafo", "saúde"],
                 category: .view, action: .run { [weak self] in self?.openMemoryPanel(nil) })
            .accepting("section=<projects|inbox|workstreams|search|graph|review|health|docs|changelog> "
                       + "[query=<words>] [scope=<workspace/project>] [kind=<kind>] [tier=<tier>] [explain=1] | project=<name> [workspace=<w>] "
                       + "[tab=<overview|agents|tokens|sessions|knowledge>|page=<path>|history=<path> [from=<id>] [to=<id>]|session=<id> [offset=<n>]|"
                       + "retrievals=<id>|agent=<claude-code|codex|…>|graph=1]") { [weak self] request in
                guard let self, let place = PanelPlace(arguments: request.arguments) else {
                    return .failed("section is one of the panel's sections, or project names a memory project")
                }
                self.openMemoryPanel(place)
                return .ok("showing \(place.arguments.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
            },
         Command(id: "memory.panel-back", title: T("Memory Panel: Back", "Painel da memória: voltar"), keywords: ["memory", "back", "memória", "voltar"],
                 category: .view, action: .run { [weak self] in _ = self?.memoryPanelPage()?.back() },
                 unavailableReason: { [weak self] in self?.memoryPanelPage()?.trail.back.isEmpty == false ? nil : T("Nothing to go back to", "Nada para voltar") }),
         Command(id: "memory.panel-forward", title: T("Memory Panel: Forward", "Painel da memória: avançar"), keywords: ["memory", "forward", "memória", "avançar"],
                 category: .view, action: .run { [weak self] in _ = self?.memoryPanelPage()?.forward() },
                 unavailableReason: { [weak self] in self?.memoryPanelPage()?.trail.forward.isEmpty == false ? nil : T("Nothing ahead", "Nada à frente") }),
         Command(id: "memory.open-in-cadex", title: T("Open the Memory Project in Cadex", "Abrir o projeto da memória no Cadex"),
                 keywords: ["memory", "project", "session", "open", "cadex", "memória", "projeto", "sessão", "abrir"], category: .view,
                 action: .run { [weak self] in self?.openChosenMemoryProject() })
            .accepting("project=<the memory project's name> [session=<the session's id>]") { [weak self] request in
                guard let self, let name = request["project"] else { return .failed("project is a memory project's name") }
                // A session still running in a Cadex terminal: that terminal (MemorySession.dc.html).
                if let id = request["session"], let found = self.app.locate({ $0.agentResume?.sessionID == id }) {
                    found.window.window.makeKeyAndOrderFront(nil)
                    found.window.projects?.select(found.space)
                    found.window.tabs?.focus(found.terminal)
                    return .ok("went to the session's terminal")
                }
                guard let folder = self.cadexFolder(forMemoryProject: name) else { return .failed("no Cadex project has this one's folder") }
                self.openInCadex(folder)
                return .ok("opened \(folder)")
            }]
    }

    func memoryPanelPage() -> MemoryPanelDocument? { tabs?.document(identity: MemoryPanelDocument.identity) as? MemoryPanelDocument }


    /// The page in the center at `place` (nil: where it was), the sidebar on its sections (inside a
    /// project, Projetos stays lit).
    func openMemoryPanel(_ place: PanelPlace?) {
        let page = memoryPanelPage() ?? makeMemoryPanel()
        tabs?.open(page)
        let next = (place ?? page.place).normalized
        if next != page.place { page.go(next) } else if !page.loaded, case .section(let section) = next { page.show(section) }
        memoryNav().select(next.section)
        memoryNav().setScope(next.normalized.searchScope?.name)
        workspace?.showMemoryNav()
    }

    func makeMemoryPanel() -> MemoryPanelDocument {
        var actions = MemoryPanelActions()
        actions.load = { [weak self] done in self?.loadMemoryOverview(done) }
        actions.read = { path, done in
            MemoryWiring.runAgentData(["panel", "--path", path]) { code, data in
                done(code == 0 ? .success(data) : .failure(PanelReadError(words: PanelOverviewData.errorText(data))))
            }
        }
        actions.go = { [weak self] place in self?.runMemoryPlace(place) }
        actions.back = { [weak self] in _ = self?.commands.run("memory.panel-back") }
        actions.forward = { [weak self] in _ = self?.commands.run("memory.panel-forward") }
        actions.closed = { [weak self] in
            guard let sidebar = self?.workspace?.sidebar, sidebar.mode == .memory else { return }
            sidebar.setMode(.work)
        }
        actions.overview.openInbox = { [weak self] in self?.runMemoryPlace(.section(.inbox)) }
        actions.overview.openProject = { [weak self] project in self?.runMemoryPlace(.project(project.ref, .overview)) }
        actions.overview.openAgents = { [weak self] project in self?.runMemoryPlace(.project(project.ref, .agents)) }
        actions.overview.openInCadex = { [weak self] project in self?.runOpenInCadex(project.name, session: nil) }
        actions.overview.inCadex = { [weak self] project in self?.cadexFolder(forMemoryProject: project.name) != nil }
        actions.project.openInCadex = { [weak self] ref, session in self?.runOpenInCadex(ref.name, session: session?.id) }
        actions.project.inCadex = { [weak self] ref in self?.cadexFolder(forMemoryProject: ref.name) != nil }
        // The inbox comes in phase F: its section says so meanwhile.
        actions.project.openInbox = { [weak self] _ in self?.runMemoryPlace(.section(.inbox)) }
        return MemoryPanelDocument(actions: actions)
    }

    private func runMemoryPlace(_ place: PanelPlace) {
        _ = commands.run("memory.show-panel", request: CommandRequest(arguments: place.arguments, folder: ""))
    }

    private func runOpenInCadex(_ project: String, session: String?) {
        var arguments = ["project": project]
        arguments["session"] = session
        _ = commands.run("memory.open-in-cadex", request: CommandRequest(arguments: arguments, folder: ""))
    }

    /// The sections in the sidebar, made once per window.
    private func memoryNav() -> MemoryPanelNav {
        if let nav = workspace?.sidebar.memoryHost as? MemoryPanelNav { return nav }
        let nav = MemoryPanelNav()
        nav.onPick = { [weak self] section in self?.runMemorySection(section) }
        // Enter in the field: Pesquisar with the words, in the project of the screen shown (plan 40 E).
        nav.onSearch = { [weak self] words in
            let scope = self?.memoryPanelPage()?.place.searchScope
            self?.runMemoryPlace(.search(PanelSearchQuery(words: words, scope: scope)))
        }
        workspace?.sidebar.setMemory(nav)
        workspace?.sidebar.setMemoryVersion(MemoryPanelInfo.upstream)
        return nav
    }

    private func runMemorySection(_ section: MemoryPanelSection) { runMemoryPlace(.section(section)) }

    /// The projects first, then the other two at once. The first read may start the engine: three
    /// at once raced to start it and all answered "did not answer" (a fresh test instance,
    /// 2026-11-19). The projects decide; the other two may fail alone.
    private func loadMemoryOverview(_ done: @escaping @MainActor (PanelLoad) -> Void) {
        guard settings.store.settings.memory.enabled else { return done(.off) }
        let paths = PanelOverviewData.paths
        MemoryWiring.runAgentData(["panel", "--path", paths[0]]) { [weak self] code, projects in
            guard code == 0 else { return done(.failed(PanelOverviewData.errorText(projects))) }
            let answers = PanelAnswers()
            for path in paths.dropFirst() {
                MemoryWiring.runAgentData(["panel", "--path", path]) { [weak self] code, data in
                    answers[path] = (code, data)
                    guard answers.count == paths.count - 1 else { return }
                    let ok = { (path: String) in answers[path].flatMap { $0.0 == 0 ? $0.1 : nil } }
                    guard let read = PanelOverviewData.parse(projects: projects, home: ok(paths[1]), notifications: ok(paths[2])) else {
                        return done(.failed(PanelOverviewData.errorText(projects)))
                    }
                    self?.memoryNavIfMade()?.setInbox(read.inbox.pending)
                    done(.data(read))
                }
            }
        }
    }

    private func memoryNavIfMade() -> MemoryPanelNav? { workspace?.sidebar.memoryHost as? MemoryPanelNav }

    /// The open or recent Cadex project whose repository the memory calls `name` (its main
    /// checkout's folder, MemoryMarker.projectName, the rule the engine names projects by).
    func cadexFolder(forMemoryProject name: String) -> String? {
        guard let projects else { return nil }
        let folders = projects.projects.map(\.folder) + projects.recent.map(\.folder)
        return folders.first { ($0 as NSString).lastPathComponent == name || MemoryMarker.projectName(folder: $0) == name }
    }

    /// Open already: go to it; a recent one: open it as the home screen does.
    private func openInCadex(_ folder: String) {
        if projects?.projects.contains(where: { $0.folder == folder }) == true { return pickProject(folder) }
        homeOpen(folder)
    }

    /// memory.open-in-cadex from ⌘K: the session chosen in a list, the screen's project, or the
    /// card chosen on the overview.
    private func openChosenMemoryProject() {
        guard let page = memoryPanelPage() else { return NSSound.beep() }
        if let (project, session) = page.chosenForCadex { return runOpenInCadex(project.name, session: session) }
        guard let name = page.overview.chosenProject?.name else { return NSSound.beep() }
        runOpenInCadex(name, session: nil)
    }
}

/// The reads' answers as they arrive, on the main thread.
@MainActor
private final class PanelAnswers {
    private var byPath: [String: (Int32, Data)] = [:]
    var count: Int { byPath.count }
    subscript(path: String) -> (Int32, Data)? {
        get { byPath[path] }
        set { byPath[path] = newValue }
    }
}

extension WorkspaceView {
    /// The sidebar on the Memória page's sections, opened if it was closed.
    func showMemoryNav() {
        if !inspectorVisible { setInspector(visible: true) }
        sidebar.setMode(.memory)
    }
}
