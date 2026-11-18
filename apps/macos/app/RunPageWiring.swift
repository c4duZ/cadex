import AppKit
import Orchestration
import Strings
import Terminal

/// What the app knows of the runs while an agent of a run works (plan 24
/// D1): the open pages, and one timer, armed only while a dispatch is live
/// or waits for a slot (the page itself has none, docs/spec/orchestration.md),
/// that records each agent's cost, fails the dispatches whose agent left
/// (exited without reporting), stops a run past its cap and hands freed
/// slots to the queue. A hook (TerminalView.agentDidChange) redraws the
/// pages at once. Nothing at all with no run.
@MainActor
final class RunWatch {
    static let shared = RunWatch()
    var pages: [RunPageDocument] = []
    /// The dispatches the owner was told are "stalled?" (once each).
    var toldStalled: Set<String> = []
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    func arm(_ tick: @escaping @MainActor () -> Void) {
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: TerminalView.agentDidChange, object: nil, queue: .main) { _ in
                // A hook changes what the page says of an agent even when the state does not.
                MainActor.assumeIsolated {
                    tick()
                    RunWatch.shared.pages.forEach { $0.refresh() }
                }
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
}

extension WindowSession {
    /// orchestration.show-run: the page in a tab (the one it has, if open).
    func showRun(_ id: String) {
        guard let book = OrchestrationController.shared.runs() else { return }
        if let open = RunWatch.shared.pages.first(where: { $0.runID == id }), tabs?.open(open) != nil { return }
        var actions = RunPageActions()
        actions.addTask = { [weak self] in self?.addRunTask(id) }
        actions.stopRun = { [weak self] in self?.stopRun(id) }
        actions.dispatch = { [weak self] in self?.dispatchTask($0) }
        actions.goToTerminal = { [weak self] in self?.goToDispatch($0) }
        actions.stop = { [weak self] in self?.stopTask($0) }
        actions.editDependencies = { [weak self] in self?.setTaskDependencies($0) }
        actions.addGate = { [weak self] in self?.addTaskGate($0) }
        actions.approveGate = { [weak self] in self?.approveTaskGate($0) }
        actions.rejectGate = { [weak self] in self?.rejectTaskGate($0) }
        actions.answer = { [weak self] in self?.answerQuestion($0) }
        actions.markDone = { [weak self] in self?.markDispatchDone($0) }
        actions.retry = { [weak self] in self?.retryTask($0) }
        let page = RunPageDocument(runID: id, book: book, actions: actions) { [weak self] in self?.live($0) }
        page.heartbeatMinutes = { OrchestrationController.shared.limits.heartbeatMinutes }
        page.slots = { [weak self] in ((self?.liveRunAgents() ?? 0) + (self?.liveRaceAgents() ?? 0), OrchestrationController.shared.limits.maxAgents) }
        page.refresh()
        page.onClose = { [weak page] in RunWatch.shared.pages.removeAll { $0 === page } }
        RunWatch.shared.pages.append(page)
        tabs?.open(page)
        // The page has no timer of its own (docs/spec/orchestration.md): the
        // watch runs only while an agent of a run works.
        if !RunGraph.live((try? book.store.all(.dispatches)) ?? []).isEmpty { armRunWatch() }
    }

    func refreshRunPages() { RunWatch.shared.pages.forEach { $0.refresh() } }

    func armRunWatch() {
        RunWatch.shared.arm { [weak self] in self?.runTick() }
    }

    /// Each live dispatch: its cost and Claude's id recorded, a working hook
    /// as a sign of life; the gone ones failed; each run held to its cap;
    /// freed slots handed to the queue. The pages are redrawn only when
    /// something changed. It stops when no agent of a run works and no try
    /// ended in the last 2 minutes (whose last cost may still be written).
    private func runTick() {
        guard let book = OrchestrationController.shared.runs() else { return RunWatch.shared.disarm() }
        let all: [Dispatch] = (try? book.store.all(.dispatches)) ?? []
        let live = RunGraph.live(all)
        let now = Date()
        var alive: Set<String> = []
        var changed = false
        // The cost of a try marked done while its agent still runs: the
        // status line writes the last turn's cost after the owner (or the
        // test's hook) marked it, and the run's spend read 0 for two of
        // three tries (2026-11-16). Only tabs still open; one write when it changes.
        let recent = all.filter { $0.state == .done && now.timeIntervalSince($0.endedAt ?? now) < 120 && $0.session != nil }
        for dispatch in recent {
            guard let claude = dispatchTerminal(dispatch)?.terminal.agentResume?.sessionID else { continue }
            changed = ((try? book.record(dispatch.id, cost: SessionCost.read(session: claude), claude: claude)) ?? false) || changed
        }
        for dispatch in live {
            guard let kit = dispatch.session?.kit else { continue }
            guard let found = dispatchTerminal(dispatch) else {
                // Just written to its tab: the shell has not started it yet.
                if now.timeIntervalSince(dispatch.startedAt) < 20 { alive.insert(kit) }
                continue
            }
            let terminal = found.terminal
            if terminal.hasForegroundProcess || now.timeIntervalSince(dispatch.startedAt) < 20 { alive.insert(kit) }
            let claude = terminal.agentResume?.sessionID
            changed = ((try? book.record(dispatch.id, cost: claude.flatMap { SessionCost.read(session: $0) }, claude: claude)) ?? false) || changed
            if terminal.agentStatus?.state == .working, dispatch.state == .starting || now.timeIntervalSince(dispatch.lastSign) > 60 {
                try? book.sign(dispatch.id)
                changed = true
            }
        }
        // The coordinating agents' cost counts in their run's spend.
        for run in ((try? book.store.all(.runs) as [Run]) ?? []) where !run.stopped && run.coordinator != nil {
            guard let claude = app.locate({ $0.agentResume?.kitSession == run.coordinator })?.terminal.agentResume?.sessionID,
                  let cost = SessionCost.read(session: claude), cost != run.coordinatorCostUsd else { continue }
            try? book.setCoordinator(run: run.id, kit: nil, cost: cost)
            changed = true
        }
        let gone = (try? book.reapOrphans { alive.contains($0) }) ?? []
        for id in gone {
            if let dispatch = all.first(where: { $0.id == id }) {
                try? book.tellCoordinator(run: dispatch.run, from: id, text: "task \(dispatch.task) failed: exited without reporting")
            }
        }
        tellStalled(RunGraph.live((try? book.store.all(.dispatches)) ?? []), book: book)
        var capped: [Dispatch] = []
        let watched = Set(live.map(\.run)).union(((try? book.store.all(.runs) as [Run]) ?? []).filter { !$0.stopped && $0.coordinator != nil }.map(\.id))
        for run in watched {
            let stopped = (try? book.enforceCap(run: run)) ?? []
            capped += stopped
            if (try? book.run(run))??.stopped == true { endCoordinator(of: run) }
        }
        endAgents(capped)
        if !gone.isEmpty { drainRunQueue() }
        dispatchOnTheirOwn()
        if changed || !gone.isEmpty || !capped.isEmpty { refreshRunPages() }
        let after: [Dispatch] = (try? book.store.all(.dispatches)) ?? []
        let waiting = ((try? book.waiting()) ?? []).isEmpty == false
        let coordinating = ((try? book.store.all(.runs) as [Run]) ?? []).contains { !$0.stopped && $0.coordinator != nil }
        if !waiting && !coordinating && RunGraph.live(after).isEmpty && !after.contains(where: { $0.state == .done && now.timeIntervalSince($0.endedAt ?? .distantPast) < 120 }) {
            RunWatch.shared.disarm()
        }
    }

    func dispatchTerminal(_ dispatch: Dispatch) -> (window: WindowSession, space: Int, terminal: TerminalView)? {
        guard let kit = dispatch.session?.kit else { return nil }
        return app.locate { $0.agentResume?.kitSession == kit }
    }

    func goToDispatch(_ id: String) {
        guard let dispatch: Dispatch = try? OrchestrationController.shared.runs()?.store.get(.dispatches, id: id),
              let found = dispatchTerminal(dispatch) else { return NSSound.beep() }
        NSApp.activate(ignoringOtherApps: true)
        found.window.window.makeKeyAndOrderFront(nil)
        found.window.projects?.select(found.space)
        found.window.tabs?.focus(found.terminal)
    }

    /// The dispatch as the app sees it now: its terminal's agent, its cost.
    func live(_ dispatch: Dispatch) -> ContenderLive? {
        guard !RunGraph.live([dispatch]).isEmpty else { return ContenderLive(state: .exited, costUsd: dispatch.costUsd) }
        guard let found = dispatchTerminal(dispatch) else { return ContenderLive(state: .starting, since: dispatch.startedAt) }
        let terminal = found.terminal
        let cost = terminal.agentResume.flatMap { SessionCost.read(session: $0.sessionID) } ?? dispatch.costUsd
        let state: ContenderLive.State
        switch terminal.agentStatus?.state {
        case .working?: state = .working
        case .blocked?: state = .waiting
        case .done?, .idle?: state = .finished
        case .failed?: state = .exited
        case .none?, nil: state = terminal.hasForegroundProcess ? .starting : .exited
        }
        return ContenderLive(state: state, since: terminal.agentQuietSince ?? dispatch.startedAt, costUsd: cost)
    }
}
