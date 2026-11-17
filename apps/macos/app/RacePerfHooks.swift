import Worktrees
import AppKit
import Orchestration

/// `make perf` and the race's test in the app (plan 24 phases C and F):
/// CADEX_PERF_RACE names a JSON file with a race to start on its own, 3 s
/// after the window opens, with no sheet: `name`, `prompt`, `repository`,
/// `base`, `agents` (`account`, `model`, `machine`), `budgetUsd`,
/// `maxMinutes`; with `pickAfter` (seconds), contender #1 wins then and the
/// others are discarded; `out` gets the race's contenders as JSON at each
/// step. Without the variable nothing runs.
extension WindowSession {
    private struct PerfRace: Decodable {
        struct Agent: Decodable {
            var account: String?
            var model: String?
            var machine: String?
        }
        var name: String
        var prompt: String
        var repository: String
        var base: String?
        var agents: [Agent]
        var budgetUsd: Double?
        var maxMinutes: Int?
        var pickAfter: Double?
        var out: String?
    }

    func startPerfRace(_ file: String) {
        guard let data = FileManager.default.contents(atPath: file), let spec = try? JSONDecoder().decode(PerfRace.self, from: data) else { return }
        let request = RaceRequest(name: spec.name, prompt: spec.prompt, repository: spec.repository, base: spec.base ?? "",
                                  agents: spec.agents.map { AgentChoice(account: $0.account, model: $0.model ?? "", machine: $0.machine ?? "") },
                                  caps: Caps(budgetUsd: spec.budgetUsd ?? 0.05, maxMinutes: spec.maxMinutes ?? 3))
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.startRace(request, askFirst: false)
            self?.writePerfRace(spec.out, step: "started")
        }
        guard let after = spec.pickAfter else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3 + after) { [weak self] in
            guard let self, let book = OrchestrationController.shared.races(), let race = try? book.races().first,
                  let first = try? book.contenders(of: race.id).first(where: { $0.index == 1 }) else { return }
            _ = try? book.pickWinner(race: race.id, contender: first.id)
            if let updated: Race = try? book.store.get(.races, id: race.id) { self.discardNow(updated) }
            self.writePerfRace(spec.out, step: "discarded")
        }
    }

    private func writePerfRace(_ out: String?, step: String) {
        guard let out, let book = OrchestrationController.shared.races(), let race = try? book.races().first,
              let contenders = try? book.contenders(of: race.id) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let line = ["step": step, "winner": race.winner ?? "", "contenders": String(decoding: (try? encoder.encode(contenders)) ?? Data(), as: UTF8.self)]
        let json = (try? JSONSerialization.data(withJSONObject: line, options: .prettyPrinted)) ?? Data()
        let before = (try? String(contentsOfFile: out, encoding: .utf8)) ?? ""
        try? (before + String(decoding: json, as: UTF8.self) + "\n").write(toFile: out, atomically: true, encoding: .utf8)
    }

    /// CADEX_PERF_NEW_TASK, a JSON file (`prompt`, `branch`, `separateCopy`, `agents` with
    /// `account` and `model`, `start`) that fills the New Task sheet when it opens and, with
    /// `start`, presses Start: the sheet, its lines and the launch stay the real ones.
    func fillPerfNewTask(_ sheet: NewTaskSheet) {
        struct Agent: Decodable { var account: String?; var model: String?; var codex: Bool? }
        struct Fill: Decodable {
            var prompt: String
            var branch: String?
            var separateCopy: Bool?
            var agents: [Agent]?
            var start: Bool?
        }
        guard let file = ProcessInfo.processInfo.environment["CADEX_PERF_NEW_TASK"], let data = FileManager.default.contents(atPath: file),
              let fill = try? JSONDecoder().decode(Fill.self, from: data) else { return }
        var request = sheet.request
        request.prompt = fill.prompt
        request.branch = fill.branch ?? ""
        request.separateCopy = fill.separateCopy ?? true
        if let agents = fill.agents {
            // The sheet's own choice for each account (with its usage), the model from the file.
            let choices = sheet.choices
            request.agents = agents.map { wanted in
                let dir = wanted.account.map(SettingsBridge.expand)
                var agent = choices.first { $0.account == dir && $0.machine.isEmpty && $0.isCodex == (wanted.codex ?? false) }
                    ?? NewTaskAgent(name: ((dir ?? "default") as NSString).lastPathComponent, account: dir)
                agent.model = wanted.model ?? ""
                return agent
            }
        }
        sheet.fill(request)
        if fill.start == true { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { sheet.pressStart() } }
    }
}
