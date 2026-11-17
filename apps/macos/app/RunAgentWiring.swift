import AgentTools
import Agents
import AppKit
import CommandPalette
import Orchestration
import SessionKit
import Strings
import Worktrees

/// Supervised agents (docs/spec/orchestration.md "Agentes supervisionados",
/// "Portões"; plan 24 D2): what a run's agent asks by `cadex run` (the caller
/// found by its token's session), the owner's gates and answers, the tasks
/// that start on their own when ready, and "stalled?" told to the owner.
extension WindowSession {
    /// A run's agent command. The caller is the dispatch (or coordinator)
    /// behind the session's token; a CADEX_DISPATCH_ID that is not it is refused.
    func answerRunAgent(_ id: String, _ request: CommandRequest) -> CommandReply {
        let controller = OrchestrationController.shared
        guard controller.isEnabled, let book = controller.runs() else { return .failed("runs are off in Cadex") }
        do {
            let caller = try book.caller(kitSession: request.kitSession, claimed: request.dispatch)
            let free = liveRunAgents() + liveRaceAgents() < controller.limits.maxAgents
            let outcome = try RunAgentAPI.handle(id, request.arguments, caller: caller, book: book, maxDepth: controller.limits.maxDepth,
                                                 hasSlot: free, maxAgents: controller.limits.maxAgents)
            if let question = outcome.ownerQuestion { tellOwner(question: question, request: request, book: book) }
            if outcome.changed {
                refreshRunPages()
                dispatchOnTheirOwn()
                armRunWatch()
            }
            return .ok(outcome.text)
        } catch let error as RunError {
            let run = (try? book.caller(kitSession: request.kitSession, claimed: nil))?.run ?? ""
            return .failed(Self.runMessage(error, run: run))
        } catch {
            return .failed("\(error)")
        }
    }

    /// The coordinating agent: a tab in the repository with `cadex claude`,
    /// its prompt (the goal) in a file, never through the shell; its session
    /// becomes the run's coordinator.
    func launchCoordinator(_ run: Run, book: RunBook) {
        guard let agent = run.autoAgent, let goal = run.goal else { return }
        switch RaceLaunch.localCommand(kit: SessionKit.shared, agent: agent, cwd: run.repository, prompt: RunLaunch.coordinatorPrompt(run: run, goal: goal),
                                       skipPermissions: settings.store.settings.agents.launchSkipPermissions) {
        case .failure(let refusal):
            say(T("The coordinator did not start", "O coordenador não começou"), refusal.message)
        case .success(let opened):
            try? book.setCoordinator(run: run.id, kit: opened.session)
            tabs?.newTab(cwd: run.repository)
            tabs?.activeTerminal?.session?.write(opened.command + "\n")
            armRunWatch()
        }
        refreshRunPages()
    }

    /// A question to the owner: the attention feed and a notification (plan 19's question kind).
    private func tellOwner(question: RunMessage, request: CommandRequest, book: RunBook) {
        let run = (try? book.run(question.run))?.name ?? ""
        AgentAttention.shared.note(.question, text: question.text, project: run, session: request.session, key: request.terminal)
        if ProcessInfo.processInfo.environment["CADEX_PERF_SHEETS"] == "1" { NSLog("Cadex told: question %@", question.text) }
        if AgentNotifier.canPost {
            app.postTerminalNotification(title: T("Question in \(run)", "Pergunta em \(run)"), subtitle: request.session, body: question.text, key: request.terminal)
        }
    }

    /// Every ready task that runs on its own (spawned, or the run's
    /// "dispatch on their own"), as its agent, from the latest done
    /// dependency's branch; past the cap it waits in the queue.
    func dispatchOnTheirOwn() {
        guard let book = OrchestrationController.shared.runs(), let ready = try? book.readyOnTheirOwn(), !ready.isEmpty else { return }
        for (task, agent) in ready {
            guard let run = try? book.run(task.run) else { continue }
            let current = WorktreesController.shared.plan(name: "x", repo: run.repository).base
            let base = RunLaunch.bases(for: task, dispatches: (try? book.dispatches(of: run.id)) ?? [], repositoryBranch: current).first ?? ""
            startDispatch(DispatchRequest(task: task.id, agent: agent, base: base), askFirst: false, auto: true)
        }
    }

    /// orchestration.add-gate.
    func addTaskGate(_ taskID: String) {
        guard let book = OrchestrationController.shared.runs(), let task: RunTask = try? book.store.get(.tasks, id: taskID) else { return }
        do { try book.addGate(task: taskID) } catch { say(T("No gate", "Sem portão"), Self.runMessage(error, run: task.run)) }
        refreshRunPages()
    }

    /// orchestration.approve-gate: only the owner (the command is not on the agent's list).
    func approveTaskGate(_ taskID: String) {
        guard let book = OrchestrationController.shared.runs(), let task: RunTask = try? book.store.get(.tasks, id: taskID) else { return }
        do { try book.approveGate(task: taskID) } catch { return say(T("Not approved", "Não aprovado"), Self.runMessage(error, run: task.run)) }
        refreshRunPages()
        dispatchOnTheirOwn()
    }

    /// orchestration.reject-gate, with the reason: the task is blocked.
    func rejectTaskGate(_ taskID: String) {
        guard let book = OrchestrationController.shared.runs(), let task: RunTask = try? book.store.get(.tasks, id: taskID) else { return }
        ask(T("Reject the gate of \(task.title)?", "Recusar o portão de \(task.title)?"),
            T("The task is blocked, and so is what waits for it.", "A tarefa fica bloqueada, e também o que espera por ela."),
            placeholder: T("Why", "Por quê")) { [weak self] reason in
            do { try book.rejectGate(task: taskID, reason: reason.isEmpty ? T("rejected", "recusado") : reason) } catch {
                self?.say(T("Not rejected", "Não recusado"), Self.runMessage(error, run: task.run))
            }
            self?.refreshRunPages()
        }
    }

    /// orchestration.answer-question: the answer goes to the asking agent's inbox.
    func answerQuestion(_ messageID: String) {
        guard let book = OrchestrationController.shared.runs(), let question: RunMessage = try? book.store.get(.messages, id: messageID) else { return }
        ask(T("Answer the question", "Responder a pergunta"), question.text, placeholder: T("Your answer", "Sua resposta")) { [weak self] text in
            guard !text.isEmpty else { return }
            do { try book.answer(messageID, text: text) } catch { self?.say(T("Not answered", "Não respondida"), Self.runMessage(error, run: question.run)) }
            self?.refreshRunPages()
        }
    }

    /// The dispatches with no sign of life for orchestration.heartbeatMinutes,
    /// told to the owner once each (plan 19's question kind); a sign again
    /// lets it be told again later.
    func tellStalled(_ dispatches: [Dispatch], book: RunBook) {
        let minutes = OrchestrationController.shared.limits.heartbeatMinutes
        let stalled = Set(RunGraph.stalled(dispatches, minutes: minutes, now: Date()))
        let told = RunWatch.shared.toldStalled
        for id in stalled.subtracting(told) {
            guard let dispatch = dispatches.first(where: { $0.id == id }) else { continue }
            let title = (try? book.store.get(.tasks, id: dispatch.task) as RunTask?)??.title ?? dispatch.task
            let run = (try? book.run(dispatch.run))?.name ?? ""
            let text = T("\(title) is stalled? No sign of life for \(minutes) min.", "\(title) parou? Sem sinal de vida há \(minutes) min.")
            let key = dispatchTerminal(dispatch).map { AppDelegate.key($0.terminal) }
            AgentAttention.shared.note(.question, text: text, project: run, key: key)
            if ProcessInfo.processInfo.environment["CADEX_PERF_SHEETS"] == "1" { NSLog("Cadex told: %@", text) }
            if AgentNotifier.canPost { app.postTerminalNotification(title: T("Stalled?", "Parado?"), subtitle: run, body: text, key: key ?? "") }
        }
        RunWatch.shared.toldStalled = stalled
    }
}

extension AppDelegate {
    /// Every hook of a dispatch's session is a sign of life (docs/spec/orchestration.md:
    /// "sem sinal de vida nem hook"): a dispatch that never spoke, or went
    /// quiet after its last hook, shows "stalled?" after orchestration.heartbeatMinutes.
    /// Nothing with runs off.
    func noteRunHook(_ event: AgentHookEvent) {
        guard OrchestrationController.shared.isEnabled, let kit = event.kitSession, let book = OrchestrationController.shared.runs(),
              let dispatch = RunGraph.live((try? book.store.all(.dispatches)) ?? []).first(where: { $0.session?.kit == kit }) else { return }
        try? book.sign(dispatch.id)
    }
}
