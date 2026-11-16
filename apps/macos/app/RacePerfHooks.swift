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

    /// CADEX_PERF_RACE_FORM: a JSON (`name`, `prompt`, `count`, `accounts`,
    /// `model`) that fills "New Race"'s sheet when it opens; the sheet, its
    /// button and the launch stay the real ones.
    func fillPerfRaceForm(_ form: NewRaceForm) {
        struct Fill: Decodable {
            var name: String
            var prompt: String
            var count: Int
            var accounts: [String?]
            var model: String
        }
        guard let file = ProcessInfo.processInfo.environment["CADEX_PERF_RACE_FORM"], let data = FileManager.default.contents(atPath: file),
              let fill = try? JSONDecoder().decode(Fill.self, from: data) else { return }
        form.fill(name: fill.name, prompt: fill.prompt, count: fill.count, accounts: fill.accounts, model: fill.model)
    }
}
