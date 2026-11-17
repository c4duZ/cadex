import AppKit
import Orchestration
import Worktrees

/// `make perf` and the run's test in the app (plan 24 D1 and F):
/// CADEX_PERF_RUN names a JSON file with a run made on its own 3 s after
/// the window opens, with no sheet: `name`, `repository`, `budgetUsd`,
/// `maxMinutes`, `tasks` (`title`, `spec`, `after`: titles), `agent`
/// (`account`, `model`). Every task that becomes ready is dispatched as the
/// owner would; with `markDoneWhenFinished`, a dispatch whose agent went
/// quiet is marked done (the owner's click, D1); with `markDoneWhenFailed`,
/// one that failed too; with `stopFirstAfter` (seconds), the first dispatch
/// is stopped then, as orchestration.stop-dispatch does; `out` gets the run's
/// tasks and dispatches at each step. CADEX_PERF_RUN_FORM fills the
/// sheets when they open. Without the variables nothing runs.
extension WindowSession {
    private struct PerfRun: Decodable {
        struct Task: Decodable {
            var title: String
            var spec: String
            var after: [String]?
        }
        struct Agent: Decodable {
            var account: String?
            var model: String?
        }
        var name: String
        var repository: String
        var budgetUsd: Double?
        var maxMinutes: Int?
        var tasks: [Task]
        var agent: Agent?
        var markDoneWhenFinished: Bool?
        var markDoneWhenFailed: Bool?
        var stopFirstAfter: Double?
        var out: String?
    }

    func startPerfRun(_ file: String) {
        guard let data = FileManager.default.contents(atPath: file), let spec = try? JSONDecoder().decode(PerfRun.self, from: data) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, let book = OrchestrationController.shared.runs(),
                  let run = try? book.newRun(name: spec.name, repository: spec.repository,
                                             caps: Caps(budgetUsd: spec.budgetUsd ?? 0.05, maxMinutes: spec.maxMinutes ?? 3)) else { return }
            var ids: [String: String] = [:]
            for task in spec.tasks {
                let made = try? book.addTask(run: run.id, title: task.title, spec: task.spec, dependsOn: (task.after ?? []).compactMap { ids[$0] })
                ids[task.title] = made?.id
            }
            self.showRun(run.id)
            let agent = AgentChoice(account: spec.agent?.account, model: spec.agent?.model ?? "")
            self.drivePerfRun(run.id, agent: agent, markDone: spec.markDoneWhenFinished ?? false, markFailed: spec.markDoneWhenFailed ?? false, out: spec.out)
            guard let after = spec.stopFirstAfter else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in
                guard let first = RunGraph.live((try? book.dispatches(of: run.id)) ?? []).first else { return }
                self?.endAgents((try? book.stop(first.id)) ?? [])
                self?.writePerfRun(spec.out, runID: run.id, step: "stopped the first")
            }
        }
    }

    /// Every 5 s, as the owner: ready tasks dispatched, quiet agents marked done.
    private func drivePerfRun(_ runID: String, agent: AgentChoice, markDone: Bool, markFailed: Bool, out: String?) {
        guard let book = OrchestrationController.shared.runs(), let run = try? book.run(runID) else { return }
        let tasks = (try? book.tasks(of: runID)) ?? []
        let dispatches = (try? book.dispatches(of: runID)) ?? []
        for task in tasks where task.state == .ready && !run.stopped {
            let current = WorktreesController.shared.plan(name: "x", repo: run.repository).base
            let base = RunLaunch.bases(for: task, dispatches: dispatches, repositoryBranch: current).first ?? ""
            startDispatch(DispatchRequest(task: task.id, agent: agent, base: base), askFirst: false)
            writePerfRun(out, runID: runID, step: "dispatched " + task.title)
        }
        if markDone {
            for dispatch in RunGraph.live(dispatches) where live(dispatch)?.state == .finished {
                markDispatchDone(dispatch.id)
                writePerfRun(out, runID: runID, step: "done " + (tasks.first { $0.id == dispatch.task }?.title ?? ""))
            }
        }
        if markFailed {
            for task in tasks where task.state == .failed {
                guard let latest = dispatches.filter({ $0.task == task.id }).max(by: { $0.attempt < $1.attempt }) else { continue }
                writePerfRun(out, runID: runID, step: "failed " + task.title)
                markDispatchDone(latest.id)
                writePerfRun(out, runID: runID, step: "done after failing " + task.title)
            }
        }
        // Read again: marking done just now may have made a task ready.
        let now = (try? book.tasks(of: runID)) ?? []
        let finished = !now.isEmpty && now.allSatisfy { $0.state == .done || $0.state == .failed || $0.state == .blocked }
        if finished || run.stopped {
            showRun(runID)
            return writePerfRun(out, runID: runID, step: "end")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.drivePerfRun(runID, agent: agent, markDone: markDone, markFailed: markFailed, out: out)
        }
    }

    private func writePerfRun(_ out: String?, runID: String, step: String) {
        guard let out, let book = OrchestrationController.shared.runs() else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let tasks = String(decoding: (try? encoder.encode((try? book.tasks(of: runID)) ?? [])) ?? Data(), as: UTF8.self)
        let dispatches = String(decoding: (try? encoder.encode((try? book.dispatches(of: runID)) ?? [])) ?? Data(), as: UTF8.self)
        let line = ["step": step, "run": String(decoding: (try? encoder.encode(try? book.run(runID))) ?? Data(), as: UTF8.self),
                    "tasks": tasks, "dispatches": dispatches]
        let json = (try? JSONSerialization.data(withJSONObject: line)) ?? Data()
        let before = (try? String(contentsOfFile: out, encoding: .utf8)) ?? ""
        try? (before + String(decoding: json, as: UTF8.self) + "\n").write(toFile: out, atomically: true, encoding: .utf8)
    }

    /// CADEX_PERF_RUN_FORM: `run` (`name`), `task` (`title`, `spec`,
    /// `after`), `dispatch` (`account`, `model`, `reuse`), `dependencies`
    /// (`after`); each fills its sheet when
    /// it opens; the sheets, their buttons and the launch stay the real ones.
    private struct RunFormFill: Decodable {
        struct RunFill: Decodable {
            var name: String
            /// 0 you dispatch, 1 ready tasks on their own, 2 an agent coordinates.
            var mode: Int?
            var account: String?
            var model: String?
            var goal: String?
            var budgetUsd: Double?
            var maxMinutes: Int?
        }
        struct TaskFill: Decodable {
            var title: String
            var spec: String
            var after: [String]?
            var gate: Bool?
        }
        struct DispatchFill: Decodable {
            var account: String?
            var model: String
            var reuse: Bool?
        }
        struct DependenciesFill: Decodable { var after: [String] }
        var run: RunFill?
        var task: TaskFill?
        var dispatch: DispatchFill?
        var dependencies: DependenciesFill?
        /// What the owner types in a one-line sheet (an answer, a reason).
        var text: String?
    }

    private func runFormFill() -> RunFormFill? {
        guard let file = ProcessInfo.processInfo.environment["CADEX_PERF_RUN_FORM"], let data = FileManager.default.contents(atPath: file) else { return nil }
        return try? JSONDecoder().decode(RunFormFill.self, from: data)
    }

    func fillPerfRunForm(_ form: NewRunForm) {
        if let fill = runFormFill()?.run {
            form.fill(name: fill.name, mode: RunMode(rawValue: fill.mode ?? 0) ?? .owner, account: fill.account, model: fill.model ?? "",
                      goal: fill.goal ?? "", budgetUsd: fill.budgetUsd, maxMinutes: fill.maxMinutes)
        }
    }

    func fillPerfTaskForm(_ form: AddTaskForm) {
        if let fill = runFormFill()?.task { form.fill(title: fill.title, spec: fill.spec, after: fill.after ?? [], gate: fill.gate ?? false) }
    }

    func fillPerfDispatchForm(_ form: DispatchForm) {
        if let fill = runFormFill()?.dispatch { form.fill(account: fill.account, model: fill.model, reuse: fill.reuse ?? false) }
    }

    func perfTypedText() -> String? { runFormFill()?.text }

    func fillPerfDependenciesForm(_ form: DependenciesForm) {
        if let fill = runFormFill()?.dependencies { form.fill(after: fill.after) }
    }

    /// CADEX_PERF_SHEETS=1: a sheet opened in a test instance is written to
    /// the log ("Cadex sheet: <title> | <text>") and answered as the owner
    /// would click its first button (or the second, `accept` false), once it
    /// is drawn: the screen may be locked, and the accessibility does not
    /// reach the sheet (2026-11-16). The sheet, its form and what follows
    /// are the real ones.
    func perfAnswer(_ alert: NSAlert, accept: Bool = true) {
        guard ProcessInfo.processInfo.environment["CADEX_PERF_SHEETS"] == "1" else { return }
        NSLog("Cadex sheet: %@ | %@", alert.messageText, alert.informativeText)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, alert.window.isVisible else { return }
            self.window.endSheet(alert.window, returnCode: accept || alert.buttons.count < 2 ? .alertFirstButtonReturn : .alertSecondButtonReturn)
        }
    }

    /// CADEX_PERF_PRESS names a file: each second (only with the variable),
    /// a line "<button title>|<n>" in it presses the n-th button with that
    /// title in this window (performClick, the click's own path), logs
    /// "Cadex pressed: …" and empties the file. With the screen locked the
    /// accessibility sees no window (2026-11-16), so the run's test in the
    /// app presses the page's buttons this way.
    func startPerfPresses() {
        guard let file = ProcessInfo.processInfo.environment["CADEX_PERF_PRESS"] else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let line = try? String(contentsOfFile: file, encoding: .utf8), !line.isEmpty else { return }
                try? "".write(toFile: file, atomically: true, encoding: .utf8)
                let parts = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|").map(String.init)
                let wanted = parts.first ?? ""
                let index = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
                // "page": the newest run's page in front, as orchestration.show-run does.
                if wanted == "page" {
                    let runs = ((try? OrchestrationController.shared.runs()?.store.all(.runs)) as [Run]??) ?? nil
                    if let newest = (runs ?? []).max(by: { $0.createdAt < $1.createdAt }) { self.showRun(newest.id) }
                    return NSLog("Cadex pressed: page")
                }
                var found: [NSButton] = []
                func walk(_ view: NSView) {
                    if let button = view as? NSButton, button.title == wanted { found.append(button) }
                    view.subviews.forEach(walk)
                }
                self.window.contentView.map(walk)
                guard found.count >= index else { return NSLog("Cadex pressed: %@ not found (%d)", wanted, found.count) }
                found[index - 1].performClick(nil)
                NSLog("Cadex pressed: %@ %d of %d", wanted, index, found.count)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
