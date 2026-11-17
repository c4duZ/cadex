import Agents
import AppKit
import Orchestration
import SourceControl
import Strings
import Terminal
import Themes
import Worktrees

/// What the app knows of the races while anyone looks or an agent runs
/// (plan 24 phase C): the open boards, each contender's diff (counted off
/// the main thread), and one timer, armed only while a board is open or a
/// local contender works, that refreshes the boards and stops an agent past
/// its race's cap. Nothing at all with no race.
@MainActor
final class RaceWatch {
    static let shared = RaceWatch()
    var boards: [RaceBoardDocument] = []
    var diffs: [String: DiffCount] = [:]
    private var counting: Set<String> = []
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    func arm(_ tick: @escaping @MainActor () -> Void) {
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: TerminalView.agentDidChange, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { RaceWatch.shared.boards.forEach { $0.refresh() } }
            }
        }
        guard timer == nil else { return }
        let next = Timer(timeInterval: 15, repeats: true) { _ in MainActor.assumeIsolated { tick() } }
        next.tolerance = 5
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    func disarm() {
        timer?.invalidate()
        timer = nil
        observer.map(NotificationCenter.default.removeObserver)
        observer = nil
    }

    /// The diff of a local contender, counted again off the main thread.
    func count(_ contender: Contender, start: String, then: @escaping @MainActor () -> Void) {
        guard contender.agent.machine.isEmpty, !counting.contains(contender.id) else { return }
        counting.insert(contender.id)
        let path = contender.worktree, id = contender.id
        DispatchQueue.global(qos: .utility).async {
            let tally = ReviewTally.of(worktree: path, start: start)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    RaceWatch.shared.counting.remove(id)
                    if let tally { RaceWatch.shared.diffs[id] = DiffCount(files: tally.files, added: tally.added, removed: tally.removed) }
                    then()
                }
            }
        }
    }
}

extension WindowSession {
    /// orchestration.show-race: the board in a tab (the one it has, if open).
    func showRace(_ id: String) {
        guard let book = OrchestrationController.shared.races() else { return }
        if let open = RaceWatch.shared.boards.first(where: { $0.raceID == id }), tabs?.open(open) != nil { return }
        var actions = RaceBoardActions()
        actions.goToTerminal = { [weak self] contender in self?.goToContender(contender) }
        actions.review = { [weak self] contender in self?.openReview(repo: contender.worktree) }
        actions.pickWinner = { [weak self] contender in
            guard let race: Race = try? book.store.get(.races, id: id) else { return }
            self?.pickWinner(race, contender)
        }
        actions.compare = { [weak self] in self?.commands.run("git.review-compare-worktrees") }
        actions.discard = { [weak self] in
            guard let race: Race = try? book.store.get(.races, id: id) else { return }
            self?.discardRace(race)
        }
        let board = RaceBoardDocument(raceID: id, book: book, colors: Self.raceColors(), actions: actions) { [weak self] in self?.live($0) }
        board.onClose = { [weak board] in RaceWatch.shared.boards.removeAll { $0 === board } }
        RaceWatch.shared.boards.append(board)
        tabs?.open(board)
        armRaceWatch()
    }

    static func raceColors() -> RaceBoardColors {
        let ui = ThemeStore.shared.current.interface
        return RaceBoardColors(background: ui.panel.nsColor, text: ui.text.nsColor, secondary: ui.secondaryText.nsColor, accent: ui.accent.nsColor)
    }

    func refreshRaceBoards() { RaceWatch.shared.boards.forEach { $0.refresh() } }

    /// The timer stays only while a board is open or a local agent of a race works.
    func armRaceWatch() {
        RaceWatch.shared.arm { [weak self] in self?.raceTick() }
    }

    private func raceTick() {
        let book = OrchestrationController.shared.races()
        let races = (try? book?.races()) ?? []
        var working = false
        for race in races where race.winner == nil {
            for contender in (try? book?.contenders(of: race.id)) ?? [] where contender.state == .working || contender.state == .starting {
                if contender.agent.machine.isEmpty { working = true }
                enforceCap(race, contender, book: book)
                RaceWatch.shared.count(contender, start: race.base) { [weak self] in self?.refreshRaceBoards() }
            }
        }
        if RaceWatch.shared.boards.contains(where: { !($0.contenders.isEmpty) }) { RemoteAgentsReader.read() }
        refreshRaceBoards()
        if RaceWatch.shared.boards.isEmpty && !working { RaceWatch.shared.disarm() }
    }

    /// Past the race's cap (cost or minutes since it started), the agent is
    /// ended like a hibernation (SIGTERM; it keeps its conversation) and the
    /// contender says why. Another machine's agent is not Cadex's to stop.
    private func enforceCap(_ race: Race, _ contender: Contender, book: RaceBook?) {
        // Once a winner is picked it is a plain task: the race's cap no longer applies.
        guard race.winner == nil, contender.agent.machine.isEmpty, let found = contenderTerminal(contender) else { return }
        let cost = found.terminal.agentResume.flatMap { SessionCost.read(session: $0.sessionID) } ?? 0
        let minutes = Date().timeIntervalSince(race.createdAt) / 60
        guard cost > race.caps.budgetUsd || minutes > Double(race.caps.maxMinutes) else { return }
        let pid = found.terminal.foregroundGroup
        if pid > 0 { kill(pid, SIGTERM) }
        try? book?.update(contender.id, state: .exited, reason: T("hit the cap", "bateu no teto"))
    }

    func contenderTerminal(_ contender: Contender) -> (window: WindowSession, space: Int, terminal: TerminalView)? {
        // Codex has no kit session: its terminal is the one in its worktree.
        if contender.agent.isCodex { return app.locate { $0.currentDirectory == contender.worktree } }
        guard let kit = contender.session?.kit else { return nil }
        return app.locate { $0.agentResume?.kitSession == kit }
    }

    func goToContender(_ contender: Contender) {
        if let found = contenderTerminal(contender) {
            NSApp.activate(ignoringOtherApps: true)
            found.window.window.makeKeyAndOrderFront(nil)
            found.window.projects?.select(found.space)
            return found.window.tabs?.focus(found.terminal) ?? ()
        }
        NSSound.beep()
    }

    /// The contender as the app sees it now.
    func live(_ contender: Contender) -> ContenderLive? {
        let diff = RaceWatch.shared.diffs[contender.id]
        if !contender.agent.machine.isEmpty {
            let session = AgentsController.shared.remote.first { $0.cwd == contender.worktree && $0.machine == contender.agent.machine }
            let state: ContenderLive.State = switch session?.status {
            case .working?: .working
            case .waiting?: .waiting
            case .other?: .unknown
            case nil: contender.state == .failed ? .exited : .unknown
            }
            return ContenderLive(state: state, since: session?.since)
        }
        let gone = !FileManager.default.fileExists(atPath: contender.worktree)
        guard let found = contenderTerminal(contender) else {
            let state: ContenderLive.State = contender.state == .starting || contender.state == .working ? .starting : .exited
            return ContenderLive(state: state, diff: diff, worktreeGone: gone)
        }
        let terminal = found.terminal
        let cost = terminal.agentResume.flatMap { SessionCost.read(session: $0.sessionID) }
        let state: ContenderLive.State
        // Codex reports nothing to the terminal: working while it runs, exited after.
        if contender.agent.isCodex {
            return ContenderLive(state: terminal.hasForegroundProcess ? .working : .exited, since: nil, costUsd: nil, diff: diff, worktreeGone: gone)
        }
        switch terminal.agentStatus?.state {
        case .working?: state = .working
        case .blocked?: state = .waiting
        case .done?, .idle?: state = .finished
        case .failed?: state = .exited
        // No report yet: starting while a program runs there, else it exited.
        case .none?, nil: state = terminal.hasForegroundProcess ? .starting : .exited
        }
        // Quiet: since it stopped; working: since the race started.
        let started = (try? OrchestrationController.shared.races()?.store.get(.races, id: contender.race) as Race?)??.createdAt
        return ContenderLive(state: state, since: terminal.agentQuietSince ?? started, costUsd: cost, diff: diff, worktreeGone: gone)
    }

    /// orchestration.pick-winner: the winner stays a plain task; the others
    /// can be deleted at once, or later by orchestration.discard-race.
    func pickWinner(_ race: Race, _ contender: Contender) {
        guard let book = OrchestrationController.shared.races(), let others = try? book.pickWinner(race: race.id, contender: contender.id) else { return }
        refreshRaceBoards()
        let names = others.filter { $0.state != .discarded }.map { ($0.worktree as NSString).lastPathComponent }
        guard !names.isEmpty, let updated: Race = try? book.store.get(.races, id: race.id) else { return }
        confirm(T("#\(contender.index) won \(race.name)", "#\(contender.index) venceu \(race.name)"),
                T("Delete the other worktrees now? Their agents stop and what was never committed in them is lost; their branches and commits stay until you delete them.\n\n",
                  "Apagar as outras worktrees agora? Os agentes delas param e o que nunca teve commit nelas se perde; as branches e os commits ficam até você apagar.\n\n") + names.joined(separator: "\n"),
                button: T("Discard the Others", "Descartar os outros")) { [weak self] in self?.discardNow(updated) }
    }

    /// orchestration.discard-race, with the list of what goes.
    func discardRace(_ race: Race) {
        guard let book = OrchestrationController.shared.races() else { return }
        let losers = ((try? book.contenders(of: race.id)) ?? []).filter { $0.id != race.winner && $0.state != .discarded }
        confirm(T("Discard \(race.name)'s other worktrees?", "Descartar as outras worktrees de \(race.name)?"),
                T("They are deleted and their agents stop; what was never committed is lost, the branches and commits stay.\n\n",
                  "Elas são apagadas e os agentes param; o que nunca teve commit se perde, as branches e os commits ficam.\n\n")
                + losers.map { ($0.worktree as NSString).lastPathComponent }.joined(separator: "\n"),
                button: T("Discard", "Descartar")) { [weak self] in self?.discardNow(race) }
    }

    func discardNow(_ race: Race) {
        guard let book = OrchestrationController.shared.races() else { return }
        var problems: [String] = []
        for contender in ((try? book.contenders(of: race.id)) ?? []) where contender.id != race.winner && contender.state != .discarded {
            if let found = contenderTerminal(contender), found.terminal.foregroundGroup > 0 { kill(found.terminal.foregroundGroup, SIGTERM) }
            if contender.agent.machine.isEmpty, FileManager.default.fileExists(atPath: contender.worktree),
               let refused = WorktreesController.shared.discard(contender.worktree, repo: race.repository) {
                problems.append((contender.worktree as NSString).lastPathComponent + ": " + refused)
            }
        }
        _ = try? book.discard(race: race.id)
        refreshRaceBoards()
        if !problems.isEmpty { say(T("Some worktrees did not go", "Algumas worktrees não foram"), problems.joined(separator: "\n")) }
    }

    /// orchestration.delete-race-branches: each branch still there listed,
    /// then `git branch -D`; a deleted one is remembered and not listed again.
    func deleteRaceBranches(_ race: Race) {
        guard let book = OrchestrationController.shared.races() else { return }
        let left = (try? book.branchesLeft(race: race.id)) ?? []
        let branches = left.map { ($0.worktree as NSString).lastPathComponent }
        guard !branches.isEmpty else { return say(T("No branch to delete", "Nenhuma branch para apagar"), race.name) }
        let title = branches.count == 1 ? T("Delete 1 branch of \(race.name)?", "Apagar 1 branch de \(race.name)?")
                                        : T("Delete \(branches.count) branches of \(race.name)?", "Apagar \(branches.count) branches de \(race.name)?")
        confirm(title, T("Their commits are lost unless another branch has them:\n\n", "Os commits delas se perdem, a não ser que outra branch os tenha:\n\n") + branches.joined(separator: "\n"),
                button: branches.count == 1 ? T("Delete Branch", "Apagar a branch") : T("Delete Branches", "Apagar as branches")) { [weak self] in
            var refused: [String] = []
            for (contender, branch) in zip(left, branches) {
                if let message = WorktreesController.shared.deleteBranch(branch, repo: race.repository) {
                    refused.append(branch + ": " + message)
                } else {
                    try? book.markBranchDeleted(contender.id)
                }
            }
            if !refused.isEmpty { self?.say(T("Some branches stayed", "Algumas branches ficaram"), refused.joined(separator: "\n")) }
        }
    }
}
