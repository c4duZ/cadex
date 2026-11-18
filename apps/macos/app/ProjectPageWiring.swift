import AppKit
import Agents
import CommandPalette
import Memory
import Orchestration
import Projects
import StateGlyph
import Strings
import Worktrees

/// A project's page in this window (plan 30 A, done with plan 29's review; docs/spec/projects.md):
/// opened by a click on the project's name in the tree and by project.show-overview, as the tab
/// "Overview" with the right panel on Memory. Its numbers come from what the app keeps (the
/// tree's tasks, the history's sessions, the costs the status line wrote, the automations, the
/// memory's wiki) and git (merges, the remote), read off the main thread each time it shows.
extension WindowSession {
    func projectPageCommands() -> [Command] {
        [Command(id: "project.show-overview", title: T("Show the Project's Page", "Mostrar a página do projeto"),
                 keywords: ["project", "overview", "page", "conversations", "automations", "projeto", "página", "visão geral"],
                 category: .view, action: .run { [weak self] in
                     guard let folder = self?.projects?.activeFolder else { return }
                     self?.openProjectPage(folder)
                 }),
         // Its sections from ⌘K (plan 34): the page on Sessions or Memory.
         Command(id: "project.show-sessions", title: T("Show the Project's Sessions", "Mostrar as sessões do projeto"),
                 keywords: ["project", "sessions", "conversations", "archive", "history", "projeto", "sessões", "conversas", "arquivo", "histórico"],
                 category: .view, action: .run { [weak self] in
                     guard let folder = self?.projects?.activeFolder else { return }
                     self?.openProjectPage(folder, section: .sessions)
                 }),
         Command(id: "project.show-memory", title: T("Show the Project's Memory", "Mostrar a memória do projeto"),
                 keywords: ["project", "memory", "pages", "rules", "decisions", "projeto", "memória", "páginas", "regras", "decisões"],
                 category: .view, action: .run { [weak self] in
                     guard let folder = self?.projects?.activeFolder else { return }
                     self?.openProjectPage(folder, section: .memory)
                 }),
         // The project's own settings, beside its Overview (plan 32 D): the defaults stay in ⌘,.
         Command(id: "project.show-settings", title: T("Show the Project's Settings", "Mostrar as configurações do projeto"),
                 keywords: ["project", "settings", "memory", "ai-memory.toml", "projeto", "configurações", "memória"],
                 category: .view, action: .run { [weak self] in
                     guard let folder = self?.projects?.activeFolder else { return }
                     self?.openProjectSettings(folder)
                 })]
    }

    func openProjectSettings(_ folder: String) {
        if let index = projects?.projects.firstIndex(where: { $0.folder == folder }) { projects?.select(index) }
        if let open = tabs?.document(identity: ProjectSettingsDocument.identity(for: folder)) { return tabs?.open(open) ?? () }
        tabs?.open(makeProjectSettings(folder))
    }

    /// The page's sections: the project's memory (its .ai-memory.toml) for now.
    func makeProjectSettings(_ folder: String) -> ProjectSettingsDocument {
        ProjectSettingsDocument(folder: folder) { [MemoryProjectForm(folder: folder)] }
    }

    /// The project's page, on a section and a line when given (plan 34 G).
    func openProjectPage(_ folder: String, section: ProjectSection = .overview, item: String? = nil) {
        if let index = projects?.projects.firstIndex(where: { $0.folder == folder }) { projects?.select(index) }
        let page = (tabs?.document(identity: ProjectPageDocument.identity(for: folder)) as? ProjectPageDocument) ?? makeProjectPage(folder)
        tabs?.open(page)
        page.show(section: section, item: item)
        // No right panel on a page (plan 34): the project's memory is in the page's Memory.
        // The history is read while a page shows it: the sessions need it.
        watchHistoryForPages()
    }

    func makeProjectPage(_ folder: String) -> ProjectPageDocument {
        var actions = ProjectPageActions()
        actions.race = { [weak self] in _ = self?.commands.run("worktrees.new-race") }
        actions.newTask = { [weak self] in _ = self?.commands.run("worktrees.new-task") }
        actions.newTaskShortcut = { [weak self] in self?.app.keymapLabel("worktrees.new-task") }
        actions.toggleAutomation = { [weak self] id in
            self?.toggleAutomation(id)
            (self?.tabs?.document(identity: ProjectPageDocument.identity(for: folder)) as? ProjectPageDocument)?.reload()
        }
        actions.openConversation = { [weak self] id in self?.openConversation(id) }
        actions.load = { [weak self] show in self?.loadProjectPage(folder, show: show) }
        // The sections (plan 34 C to F): the lines and the rendered detail, the project's settings,
        // the automations' creation and their page.
        actions.showAll = { [weak self] in self?.openProjectsPage() }
        actions.items = { [weak self] section, query in self?.projectItems(folder, section, query: query) ?? [] }
        actions.detail = { [weak self] section, id in self?.projectDetail(folder, section, id) }
        actions.sectionView = { section in section == .settings ? MemoryProjectForm(folder: folder) : nil }
        actions.createAutomation = { [weak self] in _ = self?.commands.run("orchestration.new-automation") }
        actions.openAutomations = { [weak self] in self?.openAutomationsPage() }
        // The tasks' sessions on other machines (plan 23), read over ssh only while a page shows.
        actions.shown = { shown in AgentsController.shared.pageShown(shown) }
        return ProjectPageDocument(folder: folder, actions: actions)
    }

    /// A live session comes to the front; an ended one goes on in a tab of its folder.
    private func openConversation(_ id: String) {
        // A live one, here or on another machine (its shell there, openAgent's rule).
        if let live = (AgentsController.shared.sessions + AgentsController.shared.remote).first(where: { $0.id == id }) { return openAgent(live) }
        guard let entry = AgentHistoryController.shared.entries.first(where: { $0.id == id }) else { return NSSound.beep() }
        tabs?.newTab(cwd: AgentHistoryLaunch.folder(entry))
        tabs?.activeTerminal?.typeWhenReady(AgentHistoryLaunch.resume(entry) + "\n")
    }

    private func loadProjectPage(_ folder: String, show: @escaping @MainActor (ProjectPageState) -> Void) {
        let name = projects?.projects.first { $0.folder == folder }?.name ?? (folder as NSString).lastPathComponent
        let tasks = treeModel().first { $0.id == folder }?.tasks ?? []
        let branch = treeBranches[folder] ?? ""
        let accounts = AgentsController.shared.everyAccount()
        let mine = AgentHistoryController.shared.entries.filter { Self.belongs($0.cwd, to: folder) }
        let live = AgentsController.shared.sessions
        // This project's tasks on other machines: their sessions, as the remote reading gives them.
        let remotePaths = Set(WorktreesController.shared.remoteTasks(repo: folder).map(\.path))
        let remote = AgentsController.shared.remote.filter { session in remotePaths.contains { session.cwd == $0 || session.cwd.hasPrefix($0 + "/") } }
        let automations = (try? OrchestrationController.shared.automations()?.automations()) ?? []
        let book = OrchestrationController.shared.automations()
        let lastResults = automations.reduce(into: [String: String]()) { found, job in
            if let run = (try? book?.history(of: job.id))?.first { found[job.id] = "\(run.result)" }
        }
        let wiki = MemoryPageState.wikiDir(overview: nil, root: folder, folder: MemoryKit.folder())
        DispatchQueue.global(qos: .userInitiated).async {
            let merges = Self.git(["log", "--merges", "--first-parent", "--since=30.days", "--format=%s%x09%ct"], in: folder)
            let origin = Self.git(["config", "--get", "remote.origin.url"], in: folder)
            let pages = wiki.flatMap { FileManager.default.fileExists(atPath: $0) ? MemoryWiki.tree($0).allPages : nil }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let pages { self.projectMemory[folder] = pages }
                    let now = Date()
                    let week = mine.filter { ($0.updated ?? .distantPast) > now.addingTimeInterval(-7 * 86400) }
                    let cost = week.compactMap { SessionCost.read(session: $0.id) }.reduce(0, +)
                    let lines = merges.split(separator: "\n").map { $0.split(separator: "\t", maxSplits: 1).map(String.init) }
                    let pulls = lines.contains { $0.first?.contains("pull request") == true }
                    let lastMerge = lines.first.map { line -> String in
                        let when = line.count > 1 ? Double(line[1]).map { ProjectPageWords.when(Date(timeIntervalSince1970: $0), now: now) } ?? "" : ""
                        return T("last: ", "último: ") + ProjectPageWords.mergedName(line[0]) + (when.isEmpty ? "" : ", " + when)
                    } ?? T("none in 30 days", "nenhum em 30 dias")
                    let today = Calendar.current.startOfDay(for: now)
                    let stats = [
                        ProjectPageState.Stat(label: T("Tasks open", "Tarefas abertas"), value: "\(tasks.count)",
                                              note: ProjectPageWords.tasksNote(working: tasks.filter { $0.state == .working }.count,
                                                                               needYou: tasks.filter { $0.state == .needs }.count)),
                        ProjectPageState.Stat(label: T("This week", "Esta semana"), value: ProjectPageWords.usd(cost),
                                              note: T("\(week.count) sessions · \(Set(week.map(\.account)).count) accounts",
                                                      "\(week.count) sessões · \(Set(week.map(\.account)).count) contas")),
                        ProjectPageState.Stat(label: T("Merged", "Juntados"), value: pulls ? "\(lines.count) PRs" : T("\(lines.count) merges", "\(lines.count) merges"),
                                              note: lastMerge),
                        ProjectPageState.Stat(label: T("Memory", "Memória"), value: pages.map { T("\($0.count) pages", "\($0.count) páginas") } ?? T("off", "desligada"),
                                              note: pages.map { pages in "+\(pages.filter { ($0.time ?? .distantPast) >= today }.count) " + T("today", "hoje") } ?? ""),
                    ]
                    let accountName = { (dir: String) in accounts.first { $0.dir == dir }?.name ?? (dir as NSString).lastPathComponent }
                    let talks = mine.sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }.prefix(5).map { entry in
                        let session = live.first { $0.id == entry.id }
                        let state = ProjectPageWords.state(live: session != nil, working: session?.status == .working,
                                                           asking: session?.waitingFor != nil, updated: entry.updated, now: now)
                        let place = Self.taskName(entry.cwd, project: folder) ?? (entry.branch.isEmpty ? "main" : entry.branch)
                        return ProjectPageState.Conversation(id: entry.id, state: state, title: entry.title,
                                                             detail: [place, "Claude", accountName(entry.account)].joined(separator: " · "),
                                                             when: ProjectPageWords.when(entry.updated, now: now))
                    }
                    let away = remote.map { session in
                        ProjectPageState.Conversation(id: session.id, state: session.status == .working ? .working : session.waitingFor != nil ? .needs : .done,
                                                      title: session.name, detail: [(session.cwd as NSString).lastPathComponent, "Claude", session.machine ?? ""]
                                                          .filter { !$0.isEmpty }.joined(separator: " · "),
                                                      when: ProjectPageWords.when(session.since, now: now))
                    }
                    let jobs = automations.filter { Self.automation($0, in: folder) }.map { job -> ProjectPageState.Automation in
                        let last = lastResults[job.id].map { T(" · last ", " · último ") + $0 } ?? ""
                        return ProjectPageState.Automation(id: job.id, name: job.name,
                                                           detail: job.enabled ? AutomationSchedule.label(job.recurrence) + last : T("off", "desligada"), on: job.enabled)
                    }
                    let used = Array(Set(mine.filter { ($0.updated ?? .distantPast) > now.addingTimeInterval(-30 * 86400) }.map(\.account))).sorted()
                    let chips = used.map { dir -> ProjectPageState.Account in
                        let account = accounts.first { $0.dir == dir }
                        let percent = account.flatMap(AgentUsage.current).flatMap { $0.week?.percent ?? $0.session?.percent }.map { Int($0.rounded()) }
                        return ProjectPageState.Account(name: "Claude " + accountName(dir), percent: percent)
                    }
                    let remote = origin.isEmpty ? nil : ProjectPageWords.remote(origin)
                    let place = [(folder as NSString).abbreviatingWithTildeInPath, branch, remote].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                    // The proposal's line: where, the branch, the remote, then the memory's pages and the sessions.
                    let counts = [pages.map { T("\($0.filter { !$0.relative.hasPrefix("sessions/") }.count) memory pages", "\($0.filter { !$0.relative.hasPrefix("sessions/") }.count) páginas de memória") },
                                  T("\(mine.count) sessions", "\(mine.count) sessões")].compactMap { $0 }
                    show(ProjectPageState(name: name, place: ([place] + counts).joined(separator: " · "), stats: stats, conversations: Array((away + talks).prefix(6)), automations: jobs, accounts: chips))
                }
            }
        }
    }

    /// A folder of the project: its own, or one of its tasks' (`<repo>.worktrees/…`, worktrees.root).
    static func belongs(_ cwd: String, to folder: String) -> Bool {
        cwd == folder || cwd.hasPrefix(folder + "/") || cwd.hasPrefix(folder + ".worktrees/")
            || WorktreesController.shared.store.task(cwd).map { _ in ProjectsFile.repositoryRoot(cwd) == folder } == true
    }

    static func taskName(_ cwd: String, project: String) -> String? {
        guard cwd.hasPrefix(project + ".worktrees/") else { return nil }
        return String(cwd.dropFirst(project.count + ".worktrees/".count).split(separator: "/").first ?? "")
    }

    static func automation(_ job: Automation, in folder: String) -> Bool {
        switch job.target {
        case .newWorktree(let repository): repository == folder
        case .folder(let path): belongs(path, to: folder)
        }
    }

    nonisolated static func git(_ arguments: [String], in folder: String) -> String {
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["-C", folder] + arguments
        let out = Pipe()
        git.standardOutput = out
        git.standardError = FileHandle.nullDevice
        guard (try? git.run()) != nil else { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        git.waitUntilExit()
        return git.terminationStatus == 0 ? String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }
}
