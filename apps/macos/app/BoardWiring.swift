import AppKit
import SourceControl
import CommandPalette
import Orchestration
import Sidebar
import StateGlyph
import Strings
import Terminal
import Worktrees

/// The board in this window (plan 30 B, done with plan 29's review; docs/spec/orchestration.md):
/// view.board and the title bar's board button open it as the page "Board", the title bar saying
/// "All projects". Its cards are the tree's tasks of every project here, each with what its agent
/// does or waits for, and the race, run or automation it belongs to (from the orchestration's
/// records by worktree).
extension WindowSession {
    func boardCommands() -> [Command] {
        [Command(id: "view.board", title: T("Show the Board", "Mostrar o quadro"),
                 keywords: ["board", "kanban", "tasks", "all projects", "quadro", "tarefas", "todos os projetos"], category: .view,
                 action: .run { [weak self] in self?.openBoard() })]
    }

    /// The board's button and view.board open the board, and shut it when it shows: back to the
    /// tab used before (it opened as a page over the whole center, and the button only opened it,
    /// so there was no way out; the owner, 2026-11-18). Esc on the board does the same.
    func openBoard() {
        if tabs?.activeDocument?.identity == BoardDocument.identity { return tabs?.goBack() ?? () }
        if let open = tabs?.document(identity: BoardDocument.identity) { return tabs?.open(open) ?? () }
        tabs?.open(makeBoard())
    }

    func makeBoard() -> BoardDocument {
        var actions = BoardActions()
        actions.newRace = { [weak self] in _ = self?.commands.run("worktrees.new-race") }
        actions.newTask = { [weak self] in _ = self?.commands.run("worktrees.new-task") }
        actions.open = { [weak self] id in self?.pickInTree(.task(id)) }
        actions.load = { [weak self] show in show(self?.boardCards() ?? []) }
        actions.back = { [weak self] in self?.tabs?.goBack() }
        return BoardDocument(actions: actions)
    }

    /// Every task of the window's projects as a card.
    func boardCards() -> [BoardCard] {
        let groups = boardGroups()
        let terminals = (projects?.projects ?? []).flatMap { $0.tabs.allTerminals }
        return treeModel().flatMap { project in
            project.tasks.map { task -> BoardCard in
                let mine = terminals.filter { ($0.currentDirectory ?? "") == task.id || ($0.currentDirectory ?? "").hasPrefix(task.id + "/") }
                let said = mine.lazy.compactMap { $0.agentStatus?.message }.first { !$0.isEmpty }
                let raw = !task.waiting.isEmpty ? Self.waitingText(task.waiting) : said ?? task.comment
                let text = raw.prefix(1).uppercased() + raw.dropFirst()
                let group = groups[task.id]
                return BoardCard(id: task.id, state: task.state, name: task.name, age: task.age, text: text, project: project.name,
                                 agent: task.agent.components(separatedBy: " · ").first ?? "", added: task.added, removed: task.removed,
                                 group: group?.chip, filter: group?.filter)
            }
        }
    }

    /// "approve Bash: make perf" as the mockup's card says it: "Wants to run Bash: make perf".
    static func waitingText(_ waiting: String) -> String {
        guard waiting.hasPrefix("approve ") else { return waiting }
        return T("Wants to run ", "Quer rodar ") + waiting.dropFirst("approve ".count)
    }

    /// The race, run or automation each worktree belongs to: its chip and its filter.
    private func boardGroups() -> [String: (chip: String, filter: String)] {
        var found: [String: (chip: String, filter: String)] = [:]
        let controller = OrchestrationController.shared
        if controller.isEnabled, let races = controller.races() {
            for race in (try? races.races()) ?? [] {
                for contender in (try? races.contenders(of: race.id)) ?? [] {
                    found[contender.worktree] = (T("Race: \(race.name) #\(contender.index)", "Corrida: \(race.name) #\(contender.index)"),
                                                 T("Race: \(race.name)", "Corrida: \(race.name)"))
                }
            }
        }
        if controller.isEnabled, let runs = controller.runs() {
            for run in ((try? runs.store.all(.runs)) as [Run]?) ?? [] {
                for dispatch in (try? runs.dispatches(of: run.id)) ?? [] {
                    found[dispatch.worktree] = (T("Run: \(run.name)", "Execução: \(run.name)"), T("Run: \(run.name)", "Execução: \(run.name)"))
                }
            }
        }
        if let book = controller.automations() {
            for job in (try? book.automations()) ?? [] {
                for run in (try? book.history(of: job.id)) ?? [] {
                    if let folder = run.folder { found[folder] = (T("Automation: \(job.name)", "Automação: \(job.name)"), T("Automations", "Automações")) }
                }
            }
        }
        return found
    }

    /// The title bar while the board shows: "All projects", the board's button lit.
    func showBoardChrome() {
        let on = tabs?.activeDocument?.identity == BoardDocument.identity
        workspace?.titleBar.setBoardOpen(on)
        // The board has the right panel closed (the mockup), given back when it goes; so has the
        // review, whose list is the same files (plan 31 A).
        workspace?.setBoardShown(on || tabs?.activeDocument is ReviewDocument)
        showLocation(folder.root)
    }
}
