import AppKit
import Agents
import CommandPalette
import Home
import Menus
import Orchestration
import Projects
import SessionKit
import Strings
import Terminal

/// What the owner picked on the home screen: the project the prompt is about, the account, and
/// whether it runs in a separate copy.
struct HomeChoice {
    var project: String?
    var account: String?
    var separateCopy = false
}

/// The home screen in this window (plan 29 phase A; docs/spec/home.md): shown when no project is
/// open and by home.show, gone when a project shows. Its prompt opens a terminal with the agent
/// and the owner's words as the prompt (ADR 0036, through the session kit's prompt file); its
/// cards run the commands; its recent projects open.
extension WindowSession {
    func homeCommands() -> [Command] {
        [Command(id: "home.show", title: T("Show the Home Screen", "Mostrar a tela de início"),
                 keywords: ["home", "start", "welcome", "início", "começar", "projects", "recent", "recentes"], category: .view,
                 action: .run { [weak self] in self?.showHome() })]
    }

    func showHome() {
        guard let workspace else { return }
        if home == nil {
            var actions = HomeActions()
            actions.submit = { [weak self] text in self?.homeSubmit(text) }
            actions.pickProject = { [weak self] anchor in self?.homePickProject(below: anchor) }
            actions.pickAgent = { [weak self] anchor in self?.homePickAgent(below: anchor) }
            actions.pickPlace = { [weak self] anchor in self?.homePickPlace(below: anchor) }
            actions.card = { [weak self] card in self?.homeCard(card) }
            actions.openRecent = { [weak self] folder in self?.homeOpen(folder) }
            actions.removeRecent = { [weak self] folder in
                self?.projects?.forgetRecent(folder: folder)
                self?.refreshHome()
            }
            actions.openFolder = { [weak self] in self?.chooseProjectFolder() }
            actions.clone = { [weak self] in self?.homeClone() }
            actions.shortcut = { [weak self] card in
                let key = self?.app.keymapLabel(Self.homeCommand(card == .race ? .task : card)) ?? ""
                // The Race card: New Task with a second agent (the Home mockup).
                return card == .race && !key.isEmpty ? key + T(", then + agent", ", depois + agente") : key
            }
            home = HomeView(actions: actions)
        }
        guard let home else { return }
        if homeChoice.project == nil { homeChoice.project = projects?.activeFolder ?? projects?.recent.first?.folder }
        refreshHome()
        workspace.showHome(home)
        // Again once the window is up: at launch the keymap (the cards' shortcuts) comes after.
        DispatchQueue.main.async { [weak self, weak home] in
            self?.refreshHome()
            home?.focusPrompt()
        }
    }

    /// A project shows: the screen goes and its memory with it (only built while shown).
    func hideHome() {
        workspace?.hideHome()
        home = nil
    }

    func refreshHome() {
        guard let home, let projects else { return }
        let account = homeAccount()
        let recents = projects.recent.map { recent -> HomeRecent in
            let state: HomeRecent.State
            if !FileManager.default.fileExists(atPath: recent.folder) {
                state = .missing
            } else if let open = projects.projects.first(where: { $0.folder == recent.folder }) {
                let terminals = open.tabs.allTerminals
                let finished = terminals.contains { $0.agentFinishedUnseen }
                state = HomeWords.state(terminals: terminals.count, needYou: terminals.filter { $0.agentStatus?.state == .blocked }.count,
                                        finished: finished ? "Claude" : nil)
            } else {
                state = .closed
            }
            return HomeRecent(name: recent.name, folder: recent.folder, state: state, usedAt: recent.usedAt)
        }
        let project = homeChoice.project.map { folder in
            projects.projects.first { $0.folder == folder }?.name ?? projects.recent.first { $0.folder == folder }?.name ?? (folder as NSString).lastPathComponent
        }
        home.show(HomeState(project: project, agent: account.map { ($0.provider == .codex ? "Codex · " : "Claude · ") + $0.name }, separateCopy: homeChoice.separateCopy, recents: recents))
    }

    // MARK: The prompt

    /// The account the prompt opens: the one picked, else the project's or the active one.
    private func homeAccount() -> AgentAccount? {
        // The one picked, Claude Code's or Codex's.
        if let dir = homeChoice.account, let found = AgentsController.shared.everyAccount().first(where: { $0.dir == dir }) { return found }
        let accounts = AgentsController.shared.everyAccount().filter { $0.provider == .claude }
        let agents = settings.store.settings.agents
        let projects = agents.projectAccounts.reduce(into: [String: String]()) { $0[SettingsBridge.expand($1.key)] = SettingsBridge.expand($1.value) }
        return AgentNewSession.account(cwd: homeChoice.project ?? NSHomeDirectory(), accounts: accounts,
                                       active: agents.activeAccount.isEmpty ? nil : SettingsBridge.expand(agents.activeAccount), projects: projects)
    }

    /// Enter: in this folder, a terminal in the project with the agent and the words as its prompt
    /// (ADR 0036: the owner asked, so no orchestration switch); in a separate copy, New Task.
    private func homeSubmit(_ text: String) {
        if homeChoice.separateCopy {
            guard homeChoice.project != nil else { return chooseProjectFolder() }
            homeOpenProject()
            // The New Task sheet with the words already in it (the spec).
            return showNewTask(prompt: text)
        }
        guard let account = homeAccount() else { return homeNoAccount() }
        let opened = homeOpenProject()
        let folder = opened.folder
        // A project the screen just opened came with a terminal: the agent goes there.
        let terminal: () -> Void = { [weak self] in if !opened.fresh { self?.tabs?.newTab(cwd: folder) } }
        let agent = AgentChoice(account: account.isDefault ? nil : account.dir, provider: account.provider == .codex ? "codex" : nil)
        switch RaceLaunch.localCommand(kit: SessionKit.shared, agent: agent, cwd: folder, prompt: text,
                                       skipPermissions: settings.store.settings.agents.launchSkipPermissions) {
        case .success(let launch):
            terminal()
            tabs?.activeTerminal?.typeWhenReady(launch.command + "\n")
        case .failure:
            // No `cadex` to read the prompt file (a build without it): the agent opens and the
            // words go to the clipboard, never into a shell command.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            terminal()
            tabs?.activeTerminal?.typeWhenReady(AgentLaunch.command(for: account, skipPermissions: false, cwd: folder) + "\n")
        }
    }

    /// The chosen project open and shown (the home folder without one); its folder, and whether it
    /// was opened just now (with a fresh terminal in it).
    @discardableResult
    private func homeOpenProject() -> (folder: String, fresh: Bool) {
        let folder = homeChoice.project ?? NSHomeDirectory()
        let before = projects?.projects.count ?? 0
        homeOpen(folder)
        return (folder, (projects?.projects.count ?? 0) > before)
    }

    private func homeOpen(_ folder: String) {
        self.folder.open(folder)
        projects?.open(folder: folder)
    }

    private func homeNoAccount() {
        _ = commands.run("agents.add-account")
    }

    // MARK: The menus

    private func homePickProject(below anchor: NSView) {
        guard let projects else { return }
        var seen = Set<String>()
        var entries: [MenuEntry] = []
        for (name, folder) in projects.projects.map({ ($0.name, $0.folder) }) + projects.recent.map({ ($0.name, $0.folder) })
        where seen.insert(folder).inserted && FileManager.default.fileExists(atPath: folder) {
            entries.append(MenuEntry(name, icon: homeChoice.project == folder ? .check : nil) { [weak self] in
                self?.homeChoice.project = folder
                self?.refreshHome()
            })
        }
        entries += [.separator, MenuEntry(T("Open Folder…", "Abrir pasta…"), shortcut: app.keymapLabel("workspace.open-folder")) { [weak self] in
            self?.chooseProjectFolder()
        }]
        PopupMenu.show(MenuEntry.tidy(entries), below: anchor)
    }

    private func homePickAgent(below anchor: NSView) {
        let current = homeAccount()?.dir
        var entries = AgentsController.shared.everyAccount().sorted { ($0.provider == .claude ? 0 : 1) < ($1.provider == .claude ? 0 : 1) }.map { account in
            MenuEntry((account.provider == .codex ? "Codex · " : "Claude · ") + account.name, icon: account.dir == current ? .check : nil) { [weak self] in
                self?.homeChoice.account = account.dir
                self?.refreshHome()
            }
        }
        entries += [.separator, MenuEntry(T("Add Account…", "Adicionar conta…")) { [weak self] in self?.homeNoAccount() }]
        PopupMenu.show(MenuEntry.tidy(entries), below: anchor)
    }

    private func homePickPlace(below anchor: NSView) {
        let pick: (Bool) -> Void = { [weak self] copy in
            self?.homeChoice.separateCopy = copy
            self?.refreshHome()
        }
        PopupMenu.show([
            MenuEntry(T("In this folder", "Nesta pasta"), icon: homeChoice.separateCopy ? nil : .check) { pick(false) },
            MenuEntry(T("In a separate copy (a task)", "Numa cópia separada (uma tarefa)"), icon: homeChoice.separateCopy ? .check : nil) { pick(true) },
        ], below: anchor)
    }

    // MARK: The cards and Clone

    static func homeCommand(_ card: HomeCard) -> String {
        switch card {
        case .terminal: "tab.new"
        case .agent: "agents.open-account"
        case .task: "worktrees.new-task"
        case .race: "orchestration.new-race"
        }
    }

    /// Each card runs its command in the chosen project (the home folder without one).
    private func homeCard(_ card: HomeCard) {
        // A task needs a repository: with no project at all, Open Folder first (the spec).
        if card == .task || card == .race, homeChoice.project == nil { return chooseProjectFolder() }
        let opened = homeOpenProject()
        // Terminal on a project just opened: the terminal it came with is the one.
        if card == .terminal, opened.fresh { return }
        _ = commands.run(Self.homeCommand(card))
    }

    /// `git clone` in a terminal of the parent folder, in sight; when it ends with the repository
    /// there, its project opens, and the parent's project goes if it was opened only for this.
    func homeCloneRun(_ address: String, into parent: String) {
        let name = HomeWords.cloneFolder(address)
        let target = (parent as NSString).appendingPathComponent(name)
        let before = projects?.projects.count ?? 0
        homeOpen(parent)
        let fresh = (projects?.projects.count ?? 0) > before
        if !fresh { tabs?.newTab(cwd: parent) }
        guard let terminal = tabs?.activeTerminal else { return }
        func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        terminal.typeWhenReady("git clone " + quoted(address) + " " + quoted(name) + "\n")
        CloneWatch(terminal: terminal, target: target) { [weak self] in
            self?.homeOpen(target)
            if fresh, let parentProject = self?.projects?.projects.first(where: { target.hasPrefix($0.folder + "/") })?.folder {
                self?.projects?.close(folder: parentProject)
            }
        }.start()
    }

    /// Clone…: the address, then where; `git clone` runs in a terminal there, in sight.
    private func homeClone() {
        let alert = NSAlert()
        alert.messageText = T("Clone a repository", "Clonar um repositório")
        alert.informativeText = T("The repository's address. Next, the folder it goes into.", "O endereço do repositório. Depois, a pasta onde ele fica.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "https://github.com/owner/repo.git"
        alert.accessoryView = field
        alert.addButton(withTitle: T("Next", "Seguir"))
        alert.addButton(withTitle: T("Cancel", "Cancelar")).keyEquivalent = "\u{1B}"
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                let address = field.stringValue.trimmingCharacters(in: .whitespaces)
                guard response == .alertFirstButtonReturn, !address.isEmpty, let self else { return }
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.prompt = T("Clone Here", "Clonar aqui")
                panel.beginSheetModal(for: self.window) { picked in
                    MainActor.assumeIsolated {
                        guard picked == .OK, let parent = panel.url?.path else { return }
                        self.homeCloneRun(address, into: parent)
                    }
                }
            }
        }
    }
}

/// Watches a Clone… terminal: git runs, then the shell is back at its prompt (looked at once a
/// second, for at most an hour); with the repository there, `done`.
@MainActor
final class CloneWatch {
    private weak var terminal: TerminalView?
    private let target: String
    private let done: () -> Void
    private var started = false
    private var ticks = 0
    private var clock: Timer?

    init(terminal: TerminalView, target: String, done: @escaping () -> Void) {
        self.terminal = terminal
        self.target = target
        self.done = done
    }

    func start() {
        let clock = Timer(timeInterval: 1, repeats: true) { [self] _ in MainActor.assumeIsolated { self.tick() } }
        RunLoop.main.add(clock, forMode: .common)
        self.clock = clock
    }

    private func tick() {
        ticks += 1
        guard let terminal, ticks < 3600 else { return stop() }
        if terminal.hasForegroundProcess { started = true; return }
        // Back at the prompt with the repository there: done, even when git was too quick to be
        // seen running (a local clone, under a second). Not seen running after 30 s: it failed at
        // once, or was never typed; stop looking.
        let cloned = FileManager.default.fileExists(atPath: target + "/.git")
        guard cloned || started || ticks > 30 else { return }
        stop()
        if cloned { done() }
    }

    private func stop() {
        clock?.invalidate()
        clock = nil
    }
}
