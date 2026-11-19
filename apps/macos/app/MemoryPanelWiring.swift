import AppKit
import CommandPalette
import Memory
import Sidebar
import Strings

/// The Memória page (plan 40 C; docs/plans/40-memory-panel.md): memory.show-panel opens it in the
/// center like Automations and swaps the sidebar for its sections (Memória in the sidebar's foot,
/// ⌘K, a section's line with section=); memory.open-in-cadex goes to the Cadex project with a
/// memory project's folder. The data comes from the engine's panel routes through
/// `cadex memory-agent panel --path P` (MemoryWiring.runAgentData).
extension WindowSession {
    func memoryPanelCommands() -> [Command] {
        [Command(id: "memory.show-panel", title: T("Show the Memory Panel", "Mostrar o painel da memória"),
                 keywords: ["memory", "panel", "projects", "inbox", "workstreams", "graph", "health", "memória", "painel", "projetos",
                            "caixa de entrada", "grafo", "saúde"],
                 category: .view, action: .run { [weak self] in self?.openMemoryPanel(nil) })
            .accepting("section=<projects|inbox|workstreams|search|graph|review|health|docs|changelog> [query=<words>]") { [weak self] request in
                let words = request["section"] ?? "projects"
                guard let self, let section = MemoryPanelSection(rawValue: words) else { return .failed("section is one of the panel's sections") }
                self.openMemoryPanel(section)
                return .ok("showing \(section.rawValue)")
            },
         Command(id: "memory.open-in-cadex", title: T("Open the Memory Project in Cadex", "Abrir o projeto da memória no Cadex"),
                 keywords: ["memory", "project", "open", "cadex", "memória", "projeto", "abrir"], category: .view,
                 action: .run { [weak self] in self?.openChosenMemoryProject() })
            .accepting("project=<the memory project's name>") { [weak self] request in
                guard let self, let name = request["project"], let folder = self.cadexFolder(forMemoryProject: name)
                else { return .failed("project is a memory project with a Cadex project's folder") }
                self.openInCadex(folder)
                return .ok("opened \(folder)")
            }]
    }

    /// The page in the center at `section` (nil: the last one seen), the sidebar on its sections.
    func openMemoryPanel(_ section: MemoryPanelSection?) {
        let page = (tabs?.document(identity: MemoryPanelDocument.identity) as? MemoryPanelDocument) ?? makeMemoryPanel()
        tabs?.open(page)
        let next = section ?? page.section
        if next != page.section || !page.loaded { page.show(next) }
        memoryNav().select(next)
        workspace?.showMemoryNav()
    }

    func makeMemoryPanel() -> MemoryPanelDocument {
        var actions = MemoryPanelActions()
        actions.load = { [weak self] done in self?.loadMemoryOverview(done) }
        actions.closed = { [weak self] in
            guard let sidebar = self?.workspace?.sidebar, sidebar.mode == .memory else { return }
            sidebar.setMode(.work)
        }
        actions.overview.openInbox = { [weak self] in self?.runMemorySection(.inbox) }
        // A project's own screens come in phase D: the click lands on Projetos meanwhile.
        actions.overview.openProject = { [weak self] _ in self?.runMemorySection(.projects) }
        actions.overview.openAgents = { [weak self] _ in self?.runMemorySection(.projects) }
        actions.overview.openInCadex = { [weak self] project in
            _ = self?.commands.run("memory.open-in-cadex", request: CommandRequest(arguments: ["project": project.name], folder: ""))
        }
        actions.overview.inCadex = { [weak self] project in self?.cadexFolder(forMemoryProject: project.name) != nil }
        return MemoryPanelDocument(actions: actions)
    }

    /// The sections in the sidebar, made once per window.
    private func memoryNav() -> MemoryPanelNav {
        if let nav = workspace?.sidebar.memoryHost as? MemoryPanelNav { return nav }
        let nav = MemoryPanelNav()
        nav.onPick = { [weak self] section in self?.runMemorySection(section) }
        // Pesquisar comes in phase E: Enter opens its section, which says so.
        nav.onSearch = { [weak self] _ in self?.runMemorySection(.search) }
        workspace?.sidebar.setMemory(nav)
        workspace?.sidebar.setMemoryVersion(MemoryPanelInfo.upstream)
        return nav
    }

    private func runMemorySection(_ section: MemoryPanelSection) {
        _ = commands.run("memory.show-panel", request: CommandRequest(arguments: ["section": section.rawValue], folder: ""))
    }

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

    /// memory.open-in-cadex from ⌘K: the card chosen on the overview, if any.
    private func openChosenMemoryProject() {
        guard let page = tabs?.document(identity: MemoryPanelDocument.identity) as? MemoryPanelDocument,
              let name = page.overview.chosenProject?.name else { return NSSound.beep() }
        _ = commands.run("memory.open-in-cadex", request: CommandRequest(arguments: ["project": name], folder: ""))
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
