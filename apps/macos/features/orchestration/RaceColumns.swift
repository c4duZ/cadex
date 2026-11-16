import Foundation
import Strings

/// What the app knows of a contender right now, from outside this feature:
/// its terminal's agent (OSC 7501 and the hooks, plan 19), or, on another
/// machine, `claude agents --json` (plan 23); the session's cost from the
/// `cadex statusline` file; the diff from the source-control feature.
public struct ContenderLive: Equatable, Sendable {
    public enum State: Equatable, Sendable { case starting, working, waiting, finished, exited, unknown }
    public var state: State
    /// Since when it is in that state.
    public var since: Date?
    public var costUsd: Double?
    public var diff: DiffCount?
    /// The worktree is gone (removed by hand).
    public var worktreeGone = false
    public init(state: State, since: Date? = nil, costUsd: Double? = nil, diff: DiffCount? = nil, worktreeGone: Bool = false) {
        self.state = state
        self.since = since
        self.costUsd = costUsd
        self.diff = diff
        self.worktreeGone = worktreeGone
    }
}

public struct DiffCount: Equatable, Sendable {
    public let files: Int
    public let added: Int
    public let removed: Int
    public init(files: Int, added: Int, removed: Int) {
        self.files = files
        self.added = added
        self.removed = removed
    }
}

/// One column of the race's board, ready to draw.
public struct RaceColumn: Equatable, Sendable {
    public let contender: String
    public let title: String
    public let subtitle: String
    public let state: String
    public let elapsed: String
    public let cost: String
    public let diff: String
    public let isWinner: Bool
    public let isDiscarded: Bool
    public let canCompare: Bool
}

public enum RaceColumns {
    /// The board's columns, by contender number.
    public static func make(race: Race, contenders: [Contender], live: (Contender) -> ContenderLive?, now: Date) -> [RaceColumn] {
        contenders.sorted { $0.index < $1.index }.map { contender in
            let info = live(contender)
            let discarded = contender.state == .discarded
            return RaceColumn(
                contender: contender.id,
                title: "#\(contender.index) · " + (contender.worktree as NSString).lastPathComponent,
                subtitle: agentLabel(contender.agent),
                state: discarded ? T("Discarded", "Descartado") : stateLabel(info, stored: contender),
                elapsed: info?.since.map { duration(now.timeIntervalSince($0)) } ?? "",
                cost: costLabel(info?.costUsd, remote: !contender.agent.machine.isEmpty),
                diff: discarded ? T("deleted", "apagada") : info?.worktreeGone == true ? T("worktree gone", "worktree sumiu") : diffLabel(info?.diff),
                isWinner: race.winner == contender.id,
                isDiscarded: discarded,
                canCompare: !discarded && info?.worktreeGone != true && contender.agent.machine.isEmpty)
        }
    }

    /// "opus · bkdg · pc": the model, the account's folder name, the machine.
    public static func agentLabel(_ agent: AgentChoice) -> String {
        var parts = [agent.model.isEmpty ? T("default model", "modelo padrão") : agent.model]
        parts.append(agent.account.map { ($0 as NSString).lastPathComponent } ?? "~/.claude")
        if !agent.machine.isEmpty { parts.append(agent.machine) }
        return parts.joined(separator: " · ")
    }

    static func stateLabel(_ info: ContenderLive?, stored: Contender) -> String {
        if stored.state == .failed { return T("Failed to start", "Não começou") + (stored.reason.map { ": " + $0 } ?? "") }
        // Stopped by Cadex (the cap): says so even before the process is gone.
        if stored.state == .exited, let reason = stored.reason { return T("Stopped: ", "Parado: ") + reason }
        switch info?.state {
        case .starting?: return T("Starting", "Começando")
        case .working?: return T("Working", "Trabalhando")
        case .waiting?: return T("Waiting for you", "Esperando você")
        case .finished?: return T("Finished", "Terminou")
        case .exited?: return T("Exited", "Saiu")
        case .unknown?, nil: return T("Unknown", "Desconhecido")
        }
    }

    /// "—" on another machine: its status line is not Cadex's (ADR 0031).
    static func costLabel(_ cost: Double?, remote: Bool) -> String {
        guard !remote, let cost else { return "—" }
        // A haiku answer costs a fraction of a cent (US$ 0.0048, 2026-11-16).
        return String(format: cost < 0.1 ? "US$ %.4f" : "US$ %.2f", cost)
    }

    static func diffLabel(_ diff: DiffCount?) -> String {
        guard let diff else { return "—" }
        if diff.files == 0 { return T("no changes", "sem mudanças") }
        let files = diff.files == 1 ? T("1 file", "1 arquivo") : T("\(diff.files) files", "\(diff.files) arquivos")
        return files + " +\(diff.added) −\(diff.removed)"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \(s / 60 % 60)m"
    }
}

/// A session's cost as `cadex statusline` keeps it (docs/spec/agent-tools.md):
/// `<usage>/sessions/<session id>.json`, `cost.total_cost_usd`.
public enum SessionCost {
    public static var usageFolder: String {
        if let dir = ProcessInfo.processInfo.environment["CADEX_USAGE_DIR"], !dir.isEmpty { return dir }
        return FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Application Support/Cadex/usage"
    }

    public static func read(session: String, usage: String = SessionCost.usageFolder) -> Double? {
        guard !session.contains("/"), let data = FileManager.default.contents(atPath: usage + "/sessions/" + session + ".json") else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> Double? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let cost = root["cost"] as? [String: Any] else { return nil }
        return (cost["total_cost_usd"] as? NSNumber)?.doubleValue
    }
}
