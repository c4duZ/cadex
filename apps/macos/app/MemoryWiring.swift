import AppKit
import CommandPalette
import Memory
import SessionKit
import Settings
import Strings
import Terminal
import Worktrees

/// The project memory in the app (plan 22, phase C;
/// docs/adr/0028-project-memory.md): memory.enabled puts the memory's part
/// in the session kit (or takes it out), and the first launch of each
/// version warms the engine up in the background.
@MainActor
enum MemoryWiring {
    /// Looked up once: the bundle does not change while the app runs.
    static let engine = MemoryKit.findEngine()
    static let plugin = MemoryKit.findPlugin()

    /// The settings: the part in the kit, or not. Without `cadex` there are
    /// no hooks to run (and no session token), so nothing goes in.
    static func apply(_ memory: Settings.Memory) {
        let kit = SessionKit.shared
        guard memory.enabled, let tools = kit.toolsPath else { return kit.withdraw(MemoryKit.partID) }
        kit.contribute(MemoryKit.partID, MemoryKit.part(tools: tools, engine: engine, shareAcrossAccounts: memory.shareAcrossAccounts,
                                                                 plugin: plugin,
                                                                 consolidateAt: memory.consolidateInSession ? memory.consolidateAtContext : nil))
    }
}

extension MemoryWiring {
    /// What the memory agent reads at each job (ADR 0029): on only with the
    /// memory and the agent on; the accounts as Agents sets them.
    static func writeAgentConfig(_ memory: Settings.Memory, agents: Settings.Agents) {
        let config = MemoryAgent.Config(enabled: memory.enabled && memory.backgroundAgent, dailyBudgetUsd: memory.dailyBudgetUsd,
                                        requireApproval: memory.requireApproval,
                                        configDir: MemoryAgent.accountFolder(agents.activeAccount),
                                        projectAccounts: agents.projectAccounts.compactMapValues { MemoryAgent.accountFolder($0) },
                                        claude: MemoryAgent.findClaude())
        MemoryAgent.write(config, folder: MemoryKit.folder())
    }

    /// `cadex memory-agent <words>` with the app's token; nil without `cadex`.
    static func runAgent(_ words: [String], done: @escaping @MainActor @Sendable (Int32, [String: Any]) -> Void) {
        guard let tools = SessionKit.shared.toolsPath, let token = MemoryAgent.appToken(tokens: SessionKit.tokensFolder) else {
            return done(1, ["error": "cadex is missing"])
        }
        MemoryAgent.run(tools: tools, words: words, environment: MemoryAgent.environment(engine: engine, token: token), done: done)
    }

    /// The same for a plain-text answer (`briefing`).
    static func runAgentText(_ words: [String], done: @escaping @MainActor @Sendable (Int32, String) -> Void) {
        guard let tools = SessionKit.shared.toolsPath, let token = MemoryAgent.appToken(tokens: SessionKit.tokensFolder) else {
            return done(1, "cadex is missing")
        }
        MemoryAgent.runText(tools: tools, words: words, environment: MemoryAgent.environment(engine: engine, token: token), done: done)
    }

    /// The same, the bytes as printed (the Memória page's routes, plan 40 C).
    static func runAgentData(_ words: [String], input: String? = nil, done: @escaping @MainActor @Sendable (Int32, Data) -> Void) {
        guard let tools = SessionKit.shared.toolsPath, let token = MemoryAgent.appToken(tokens: SessionKit.tokensFolder) else {
            return done(1, Data(#"{"error":"cadex is missing"}"#.utf8))
        }
        MemoryAgent.runData(tools: tools, words: words, input: input, environment: MemoryAgent.environment(engine: engine, token: token), done: done)
    }

    /// The same with `input` on stdin (`write-page`'s body).
    static func runAgent(_ words: [String], input: String, done: @escaping @MainActor @Sendable (Int32, [String: Any]) -> Void) {
        guard let tools = SessionKit.shared.toolsPath, let token = MemoryAgent.appToken(tokens: SessionKit.tokensFolder) else {
            return done(1, ["error": "cadex is missing"])
        }
        MemoryAgent.run(tools: tools, words: words, input: input, environment: MemoryAgent.environment(engine: engine, token: token), done: done)
    }
}

extension AppDelegate {
    /// Once per version, with memory on: the migrations and macOS's check
    /// of the new binary happen now, not in the first SessionStart's 1 s.
    func startMemory() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.showMemoryAgentNotice() }
        // A task marked ready is a consolidation milestone for the agents
        // working in it (plan 22 phase F): the hook asks at their next Stop.
        WorktreesController.shared.onStatusChange = { [weak self] status, path in
            guard status == .review, let self else { return }
            let memory = self.settings.store.settings.memory
            guard memory.enabled, memory.consolidateInSession else { return }
            for terminal in self.sessions.flatMap({ window in (window.projects?.projects ?? []).flatMap { $0.tabs.allTerminals } }) {
                guard let resume = terminal.agentResume, resume.folder == path || resume.folder.hasPrefix(path + "/") else { continue }
                MemoryKit.requestConsolidation(sessionID: resume.sessionID)
            }
        }
        guard settings.store.settings.memory.enabled, let engine = MemoryWiring.engine else { return }
        MemoryWarmUp.start(engine: engine, folder: MemoryKit.folder(), version: updates.currentVersion)
    }
}

extension WindowSession {
    /// memory.consolidate-now: the request pasted into the focused agent,
    /// without Enter (the owner sends it), as review comments are.
    func memoryCommands() -> [Command] {
        [Command(id: "memory.consolidate-now", title: T("Consolidate Memory Now", "Consolidar a memória agora"),
                 keywords: ["memory", "consolidate", "save", "lessons", "memória", "consolidar", "salvar"], category: .terminal,
                 action: .run { [weak self] in self?.consolidateNow() }),
         // The memory agent (ADR 0029): each asks the engine through `cadex memory-agent`.
         Command(id: "memory.bootstrap", title: T("Organize History with AI…", "Organizar o histórico com IA…"),
                 keywords: ["memory", "history", "bootstrap", "organize", "memória", "histórico", "organizar"], category: .terminal,
                 action: .run { [weak self] in self?.organizeHistory() }),
         Command(id: "memory.run-dream", title: T("Reorganize Memory Now (Dream)", "Reorganizar a memória agora (dream)"),
                 keywords: ["memory", "dream", "reorganize", "memória", "reorganizar"], category: .terminal,
                 action: .run { [weak self] in self?.memoryAgentAct(["dream", "--cwd", self?.projectRoot ?? NSHomeDirectory()]) }),
         Command(id: "memory.pause-agent", title: T("Pause or Resume the Memory Agent", "Pausar ou retomar o agente de memória"),
                 keywords: ["memory", "agent", "pause", "resume", "memória", "agente", "pausar", "retomar"], category: .terminal,
                 action: .run { [weak self] in self?.togglePauseAgent() })]
    }

    /// Bootstrap: the estimate first, then only on the owner's yes (ADR 0029).
    private func organizeHistory() {
        guard settings.store.settings.memory.enabled else { return NSSound.beep() }
        let cwd = projectRoot ?? NSHomeDirectory()
        MemoryWiring.runAgent(["bootstrap", "--cwd", cwd, "--dry-run"]) { [weak self] code, answer in
            guard let self, code == 0 else { return self?.agentAlert(T("The memory agent did not answer", "O agente de memória não respondeu"), answer) ?? () }
            let usd = (answer["estimate_usd"] as? NSNumber)?.doubleValue ?? 0
            let sessions = (answer["sessions"] as? NSNumber)?.intValue ?? 0
            let alert = NSAlert()
            alert.messageText = T("Organize this project's history with AI?", "Organizar o histórico deste projeto com IA?")
            alert.informativeText = T("Your account's Claude reads the \(sessions) imported sessions and writes the decisions, gotchas and concepts it finds. Estimate: up to US$ \(String(format: "%.2f", usd)), within the daily cap.",
                                      "O Claude da sua conta lê as \(sessions) sessões importadas e escreve as decisões, armadilhas e conceitos que achar. Estimativa: até US$ \(String(format: "%.2f", usd)), dentro do teto do dia.")
            alert.addButton(withTitle: T("Organize", "Organizar"))
            alert.addButton(withTitle: T("Cancel", "Cancelar"))
            alert.beginSheetModal(for: self.window) { response in
                guard response == .alertFirstButtonReturn else { return }
                self.memoryAgentAct(["bootstrap", "--cwd", cwd])
            }
        }
    }

    private func togglePauseAgent() {
        MemoryWiring.runAgent(["status"]) { [weak self] _, status in
            let paused = status["paused"] as? Bool ?? false
            self?.memoryAgentAct([paused ? "resume" : "pause"])
        }
    }

    private func memoryAgentAct(_ words: [String]) {
        guard settings.store.settings.memory.enabled else { return NSSound.beep() }
        MemoryWiring.runAgent(words) { [weak self] code, answer in
            if code != 0 { self?.agentAlert(T("The memory agent refused", "O agente de memória recusou"), answer) }
        }
    }

    private func agentAlert(_ title: String, _ answer: [String: Any]) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = answer["error"] as? String ?? ""
        alert.beginSheetModal(for: window)
    }

    private func consolidateNow() {
        let memory = settings.store.settings.memory
        guard memory.enabled, memory.consolidateInSession, let terminal = tabs?.activeTerminal,
              terminal.agentResume != nil, terminal.pasteFromApp(MemoryKit.consolidateNowText, images: []) else { return NSSound.beep() }
        tabs?.focus(terminal)
    }
}

extension AppDelegate {
    /// Once: the memory agent is on by default (ADR 0037), runs `claude -p` on the account with a
    /// daily cap, and here is how to turn it off. The ADR asked for it on the first opening; nobody
    /// was told (UX audit, 2026-11-18).
    func showMemoryAgentNotice() {
        let memory = settings.store.settings.memory
        guard memory.enabled, memory.backgroundAgent, !memory.agentNoticeShown,
              let window = sessions.first?.window else { return }
        settings.store.update { $0.memory.agentNoticeShown = true }
        let alert = NSAlert()
        alert.messageText = T("The memory agent is on", "O agente de memória está ligado")
        alert.informativeText = T(
            "After your sessions, a short `claude -p` on your account organizes what the agents learned into the project's memory, up to US$ \(Self.money(memory.dailyBudgetUsd)) a day. It uses your plan's usage. You can turn it off here or later in Settings › Memory; an API key (apiKeyHelper) can pay for it instead.",
            "Depois das suas sessões, um `claude -p` curto na sua conta organiza o que os agentes aprenderam na memória do projeto, até US$ \(Self.money(memory.dailyBudgetUsd)) por dia. Ele usa o uso do seu plano. Dá para desligar aqui ou depois em Configurações › Memória; uma chave de API (apiKeyHelper) pode pagar no lugar.")
        alert.addButton(withTitle: T("Keep On", "Manter ligado"))
        alert.addButton(withTitle: T("Turn Off", "Desligar"))
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                if response == .alertSecondButtonReturn { self?.settings.store.update { $0.memory.backgroundAgent = false } }
            }
        }
    }

    static func money(_ value: Double) -> String { String(format: "%.2f", value) }
}
