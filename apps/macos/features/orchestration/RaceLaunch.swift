import Foundation
import SessionKit
import Strings

/// What "New Race" asks (docs/spec/orchestration.md, "Corrida").
public struct RaceRequest: Equatable, Sendable {
    public var name: String
    public var prompt: String
    public var repository: String
    /// The branch every contender starts from.
    public var base: String
    public var agents: [AgentChoice]
    public var caps: Caps
    public init(name: String, prompt: String, repository: String, base: String, agents: [AgentChoice], caps: Caps) {
        self.name = name
        self.prompt = prompt
        self.repository = repository
        self.base = base
        self.agents = agents
        self.caps = caps
    }
}

/// Why a race does not start; said before anything is made.
public enum RaceRefusal: Error, Equatable {
    case off
    case tooFew
    case tooMany(Int)
    case emptyPrompt
    case promptTooBig(Int)
    /// The accounts (their folders' names) whose Claude Code does not trust
    /// the repository yet: the race would stop at the trust dialog.
    case notTrusted([String])
    case noCadex

    public var message: String {
        switch self {
        case .off: return T("Races and runs are off in Settings › General › Many Agents.", "Corridas e execuções estão desligadas em Configurações › Geral › Muitos agentes.")
        case .tooFew: return T("A race needs at least 2 agents.", "Uma corrida precisa de pelo menos 2 agentes.")
        case .tooMany(let max): return T("At most \(max) agents at once (Settings › Many Agents).", "No máximo \(max) agentes ao mesmo tempo (Configurações › Muitos agentes).")
        case .emptyPrompt: return T("The prompt is empty.", "O prompt está vazio.")
        case .promptTooBig(let bytes): return T("The prompt has \(bytes / 1024) KB; the limit is 100 KB.", "O prompt tem \(bytes / 1024) KB; o limite é 100 KB.")
        case .notTrusted(let accounts):
            return T("Claude Code does not trust this repository yet in: \(accounts.joined(separator: ", ")). Open Claude in the repository with that account and accept, then start the race again.",
                     "O Claude Code ainda não confia neste repositório em: \(accounts.joined(separator: ", ")). Abra o Claude no repositório com essa conta e aceite, depois comece a corrida de novo.")
        case .noCadex: return T("The cadex program is missing from the app, so the prompt cannot reach the agent safely.", "Falta o programa cadex no app, então o prompt não chega ao agente com segurança.")
        }
    }
}

public enum RaceLaunch {
    /// Checks a request before any worktree or tab: on, 2 to `maxAgents`
    /// agents, a prompt that fits, and every local account trusting the
    /// repository (`trusts` answers for an account's folder, nil the
    /// default). Another machine's trust is not read: its dialog, if any,
    /// shows in its tab (ADR 0033).
    public static func check(_ request: RaceRequest, enabled: Bool, maxAgents: Int, trusts: (String?) -> Bool) -> RaceRefusal? {
        guard enabled else { return .off }
        guard request.agents.count >= 2 else { return .tooFew }
        guard request.agents.count <= maxAgents else { return .tooMany(maxAgents) }
        guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .emptyPrompt }
        let bytes = Data(request.prompt.utf8).count
        guard bytes <= PromptFiles.maxBytes else { return .promptTooBig(bytes) }
        var seen: Set<String> = []
        // Claude Code's trust; Codex asks nothing of the kind.
        let untrusted = request.agents.filter { $0.machine.isEmpty && !$0.isCodex }.compactMap { agent -> String? in
            let key = agent.account ?? ""
            guard seen.insert(key).inserted, !trusts(agent.account) else { return nil }
            return agent.account.map { ($0 as NSString).lastPathComponent } ?? "~/.claude"
        }
        return untrusted.isEmpty ? nil : .notTrusted(untrusted)
    }

    /// The words after `claude` for an agent: its model, and the account's
    /// choice of no permission prompts.
    public static func arguments(_ agent: AgentChoice, skipPermissions: Bool) -> [String] {
        if agent.isCodex {
            return (agent.model.isEmpty ? [] : ["-m", agent.model]) + (skipPermissions ? ["--dangerously-bypass-approvals-and-sandbox"] : [])
        }
        return (agent.model.isEmpty ? [] : ["--model", agent.model]) + (skipPermissions ? ["--dangerously-skip-permissions"] : [])
    }

    /// The tab's command for a local contender: the prompt written to its
    /// file, then `cadex claude` with the kit; the session's key. Nil, with
    /// the reason, when the prompt cannot be written or there is no `cadex`.
    @MainActor
    /// `sessionEnvironment`: a dispatch's CADEX_DISPATCH_ID (plan 24 D1).
    public static func localCommand(kit: SessionKit, agent: AgentChoice, cwd: String, prompt: String, skipPermissions: Bool,
                                    sessionEnvironment: [String: String] = [:],
                                    promptFolder: String = PromptFiles.folder) -> Result<(command: String, session: String), RaceRefusal> {
        guard kit.toolsPath != nil else { return .failure(.noCadex) }
        switch PromptFiles.write(prompt, in: promptFolder) {
        case .failure(.tooBig(let bytes)): return .failure(.promptTooBig(bytes))
        case .failure: return .failure(.emptyPrompt)
        case .success(let file) where agent.isCodex:
            // Codex: no kit session; the race finds its terminal by the worktree (RaceBoardWiring).
            guard let command = kit.codexCommand(home: agent.account, arguments: arguments(agent, skipPermissions: skipPermissions), promptFile: file) else {
                try? FileManager.default.removeItem(atPath: file)
                return .failure(.noCadex)
            }
            return .success((command, ""))
        case .success(let file):
            guard let opened = kit.claudeCommand(configDir: agent.account, arguments: arguments(agent, skipPermissions: skipPermissions),
                                                 cwd: cwd, promptFile: file, sessionEnvironment: sessionEnvironment) else {
                try? FileManager.default.removeItem(atPath: file)
                return .failure(.noCadex)
            }
            return .success(opened)
        }
    }

    /// `<name>-<n>`: the task names, so the worktrees are `<branch>-1…N`.
    public static func taskName(_ name: String, index: Int) -> String { "\(name)-\(index)" }
}
