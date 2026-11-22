import Foundation

/// The feature's entry point for the app (docs/spec/orchestration.md): the
/// settings, and the state, opened only with the feature on. Off, nothing
/// is opened, read or timed (plan 24, "custo zero"): the store is made the
/// first time someone asks for it with the feature on, and closed when it
/// goes off.
@MainActor
public final class OrchestrationController {
    public static let shared = OrchestrationController()

    /// The settings (orchestration.* in settings.json), set by the app.
    public struct Limits: Equatable, Sendable {
        public var maxAgents = 6
        public var maxDepth = 2
        public var heartbeatMinutes = 10
        public var keepAwakeDuringRuns = true
        public var defaultBudgetUsd = 5.0
        public var defaultMaxMinutes = 60
        public init() {}
    }

    /// orchestration.enabled: races and runs. Off closes the state.
    public var isEnabled = false {
        didSet { if !isEnabled && !automationsEnabled { close() } }
    }
    /// orchestration.automations. Off closes the state when races and runs are off too.
    public var automationsEnabled = false {
        didSet {
            if !isEnabled && !automationsEnabled { close() }
            if automationsEnabled != oldValue { onAutomationsSwitch?(automationsEnabled) }
        }
    }
    /// orchestration.automations changed (Settings, or the command): the app
    /// installs or removes the LaunchAgent (docs/adr/0034-scheduled-automations.md).
    public var onAutomationsSwitch: ((Bool) -> Void)?
    public var limits = Limits()

    /// Where state.sqlite lives: CADEX_ORCHESTRATION_DIR for a test
    /// instance, never the owner's; a test's own folder.
    public var folder = ProcessInfo.processInfo.environment["CADEX_ORCHESTRATION_DIR"].flatMap { $0.isEmpty ? nil : $0 }
        ?? FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Application Support/Cadex/orchestration"
    public var statePath: String { folder + "/state.sqlite" }
    /// The automations' files (AutomationFiles), beside the state.
    public var automationsFolder: String { folder + "/automations" }

    private var store: OrchestrationStore?

    public init() {}

    /// The caps a new race, run or automation proposes.
    public var defaultCaps: Caps { Caps(budgetUsd: limits.defaultBudgetUsd, maxMinutes: limits.defaultMaxMinutes) }

    /// The state, opened on first use; nil with the feature off (or when
    /// the file cannot be opened, said once in the log).
    public func openStore() -> OrchestrationStore? {
        guard isEnabled || automationsEnabled else { return nil }
        if let store { return store }
        do {
            store = try OrchestrationStore(path: statePath)
        } catch {
            NSLog("Cadex orchestration: the state did not open (\(error))")
        }
        return store
    }

    public var isOpen: Bool { store != nil }

    public func runs() -> RunBook? { openStore().map(RunBook.init) }
    public func races() -> RaceBook? { openStore().map(RaceBook.init) }
    public func automations() -> AutomationBook? { automationsEnabled ? openStore().map { AutomationBook(store: $0, folder: automationsFolder) } : nil }

    func close() { store = nil }

    /// What the session kit puts in the `env` of a dispatch's session
    /// (`SessionKit.launch(sessionEnvironment:)`): the dispatch it belongs
    /// to, which the agent's `cadex` reports with. Never the only check: the
    /// app matches the session's token to the dispatch it recorded.
    public nonisolated static func sessionEnvironment(dispatch: String) -> [String: String] {
        ["CADEX_DISPATCH_ID": dispatch]
    }
}
