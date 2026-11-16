import Memory
import SessionKit
import Settings

/// The project memory in the app (plan 22, phase C;
/// docs/adr/0028-project-memory.md): memory.enabled puts the memory's part
/// in the session kit (or takes it out), and the first launch of each
/// version warms the engine up in the background.
@MainActor
enum MemoryWiring {
    /// Looked up once: the bundle does not change while the app runs.
    static let engine = MemoryKit.findEngine()

    /// The settings: the part in the kit, or not. Without `cadex` there are
    /// no hooks to run (and no session token), so nothing goes in.
    static func apply(_ memory: Settings.Memory) {
        let kit = SessionKit.shared
        guard memory.enabled, let tools = kit.toolsPath else { return kit.withdraw(MemoryKit.partID) }
        kit.contribute(MemoryKit.partID, MemoryKit.part(tools: tools, engine: engine, shareAcrossAccounts: memory.shareAcrossAccounts))
    }
}

extension AppDelegate {
    /// Once per version, with memory on: the migrations and macOS's check
    /// of the new binary happen now, not in the first SessionStart's 1 s.
    func startMemory() {
        guard settings.store.settings.memory.enabled, let engine = MemoryWiring.engine else { return }
        MemoryWarmUp.start(engine: engine, folder: MemoryKit.folder(), version: updates.currentVersion)
    }
}
