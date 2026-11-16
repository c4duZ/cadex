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

extension AppDelegate {
    /// Once per version, with memory on: the migrations and macOS's check
    /// of the new binary happen now, not in the first SessionStart's 1 s.
    func startMemory() {
        // A task marked ready is a consolidation milestone for the agents
        // working in it (plan 22 phase F): the hook asks at their next Stop.
        WorktreesController.shared.onStatusChange = { [weak self] status, path in
            guard status == .review, let self else { return }
            let memory = self.settings.store.settings.memory
            guard memory.enabled, memory.consolidateInSession else { return }
            for terminal in self.sessions.flatMap({ window in (window.spaces?.spaces ?? []).flatMap { $0.tabs.allTerminals } }) {
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
                 action: .run { [weak self] in self?.consolidateNow() })]
    }

    private func consolidateNow() {
        let memory = settings.store.settings.memory
        guard memory.enabled, memory.consolidateInSession, let terminal = tabs?.activeTerminal,
              terminal.agentResume != nil, terminal.pasteFromApp(MemoryKit.consolidateNowText, images: []) else { return NSSound.beep() }
        tabs?.focus(terminal)
    }
}
