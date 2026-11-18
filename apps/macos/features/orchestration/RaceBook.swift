import Foundation

/// A race's records (docs/spec/orchestration.md, "Corrida"): the race, one
/// contender per agent with worktree `<task>-<index>` from the same commit,
/// the winner and the discarded ones. Making worktrees and opening tabs is
/// the caller's (phase C); this keeps what happened.
public final class RaceBook {
    public let store: OrchestrationStore
    public var now: () -> Date = Date.init
    public var newId: () -> String = { UUID().uuidString.lowercased() }

    public init(store: OrchestrationStore) { self.store = store }

    /// Refused with fewer than 2 contenders or more than `maxAgents`.
    public func newRace(name: String, prompt: String, repository: String, base: String, caps: Caps,
                        agents: [AgentChoice], worktree: (Int) -> String, maxAgents: Int) throws -> (Race, [Contender]) {
        guard agents.count >= 2, agents.count <= maxAgents else { throw RunError.noSlot(maxAgents) }
        let race = Race(id: newId(), name: name, prompt: prompt, repository: repository, base: base, caps: caps, createdAt: now())
        let contenders = agents.enumerated().map { offset, agent in
            Contender(id: newId(), race: race.id, index: offset + 1, agent: agent, worktree: worktree(offset + 1), state: .starting)
        }
        try store.batch {
            try store.put(.races, id: race.id, race)
            for contender in contenders { try store.put(.contenders, id: contender.id, parent: race.id, contender) }
        }
        return (race, contenders)
    }

    public func races() throws -> [Race] { try store.all(.races) }
    public func contenders(of race: String) throws -> [Contender] { try store.all(.contenders, parent: race) }

    /// A contender's state from its hooks (or `claude agents --json`), its
    /// session once known, and why it failed.
    public func update(_ id: String, state: ContenderState, session: SessionLink? = nil, reason: String? = nil, worktree: String? = nil) throws {
        guard var contender: Contender = try store.get(.contenders, id: id) else { throw RunError.unknown(id) }
        contender.state = state
        contender.worktree = worktree ?? contender.worktree
        contender.session = session ?? contender.session
        contender.reason = reason ?? contender.reason
        try store.put(.contenders, id: id, parent: contender.race, contender)
    }

    /// `orchestration.pick-winner`; returns the others, the ones that
    /// `discard` deletes.
    public func pickWinner(race id: String, contender winner: String) throws -> [Contender] {
        guard var race: Race = try store.get(.races, id: id) else { throw RunError.unknown(id) }
        let all = try contenders(of: id)
        guard all.contains(where: { $0.id == winner }) else { throw RunError.unknown(winner) }
        race.winner = winner
        try store.put(.races, id: id, race)
        return all.filter { $0.id != winner }
    }

    /// The discarded contenders whose branch is still there, for
    /// orchestration.delete-race-branches.
    public func branchesLeft(race id: String) throws -> [Contender] {
        try contenders(of: id).filter { $0.state == .discarded && $0.branchDeleted != true && $0.agent.machine.isEmpty }
    }

    public func markBranchDeleted(_ id: String) throws {
        guard var contender: Contender = try store.get(.contenders, id: id) else { throw RunError.unknown(id) }
        contender.branchDeleted = true
        try store.put(.contenders, id: id, parent: contender.race, contender)
    }

    /// `orchestration.discard-race`: every contender but the winner is
    /// marked discarded (their worktrees were deleted; the branches stay
    /// until orchestration.delete-race-branches).
    public func discard(race id: String) throws -> [Contender] {
        guard var race: Race = try store.get(.races, id: id) else { throw RunError.unknown(id) }
        var out: [Contender] = []
        try store.batch {
            for var contender in try contenders(of: id) where contender.id != race.winner {
                contender.state = .discarded
                try store.put(.contenders, id: contender.id, parent: id, contender)
                out.append(contender)
            }
            race.discarded = true
            try store.put(.races, id: id, race)
        }
        return out
    }
}

/// Automations and their history (docs/spec/orchestration.md,
/// "Automações"). Scheduling and the LaunchAgent are phase E.
public final class AutomationBook {
    public let store: OrchestrationStore
    public var newId: () -> String = { UUID().uuidString.lowercased() }

    public init(store: OrchestrationStore) { self.store = store }

    public func save(_ automation: Automation) throws { try store.put(.automations, id: automation.id, automation) }
    public func automations() throws -> [Automation] { try store.all(.automations) }
    public func enabled() throws -> [Automation] { try automations().filter(\.enabled) }

    public func setEnabled(_ id: String, _ on: Bool) throws {
        guard var automation: Automation = try store.get(.automations, id: id) else { throw RunError.unknown(id) }
        automation.enabled = on
        try save(automation)
    }

    /// An automation and its history, gone (the Automations page's Delete…, plan 34 F).
    public func delete(_ id: String) throws {
        try store.batch {
            for run in try history(of: id) { try store.delete(.automationRuns, id: run.id) }
            try store.delete(.automations, id: id)
        }
    }

    /// A run of an automation, new or updated.
    public func record(_ run: AutomationRun) throws { try store.put(.automationRuns, id: run.id, parent: run.automation, run) }

    /// Newest first.
    public func history(of automation: String) throws -> [AutomationRun] {
        try (store.all(.automationRuns, parent: automation) as [AutomationRun]).sorted { $0.scheduledAt > $1.scheduledAt }
    }

    /// The automation's run still going, if any: a new one due then is
    /// skipped, "still running".
    public func running(_ automation: String) throws -> AutomationRun? {
        try history(of: automation).first { $0.result == .running }
    }
}
