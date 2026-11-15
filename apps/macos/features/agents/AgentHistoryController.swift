import CoreServices
import Foundation
import SessionKit

/// The history for the whole app (docs/spec/agents.md, Histórico): the
/// index brought up to the disk and the projects/ folders of the accounts
/// watched only while the History page shows; closed, the index stays on
/// disk and nothing runs. agents.history off: nothing indexed or watched.
@MainActor
public final class AgentHistoryController {
    public static let shared = AgentHistoryController()

    /// The conversations with at least one message, newest first.
    public internal(set) var entries: [AgentHistoryEntry] = []
    /// While the first reading runs: files done of the total.
    public internal(set) var progress: (done: Int, total: Int)?
    public var isEnabled = true { didSet { if isEnabled != oldValue { restart() } } }
    /// The accounts whose transcripts count.
    var accounts: () -> [AgentAccount] = { AgentsController.shared.everyAccount() }
    lazy var store = AgentHistoryStore(path: AgentHistoryStore.file(home: AgentsController.shared.homeFolder))

    private var watchers: [UUID: () -> Void] = [:]
    private var stream: FSEventStreamRef?
    private var running = false
    private var again = false

    public func watch(_ changed: @escaping () -> Void) -> UUID {
        let id = UUID()
        watchers[id] = changed
        if watchers.count == 1 { restart() } else { changed() }
        return id
    }

    public func stop(_ id: UUID) {
        watchers[id] = nil
        if watchers.isEmpty { restart() }
    }

    var isWatching: Bool { stream != nil }

    private func restart() {
        if let stream { Self.end(stream) }
        stream = nil
        guard isEnabled, !watchers.isEmpty else { return publish() }
        startWatching()
        refresh()
    }

    /// Brings the index up to the disk off the main thread; changes that
    /// arrive meanwhile ask for one more pass.
    func refresh() {
        guard isEnabled, !watchers.isEmpty else { return }
        if running { return again = true }
        running = true
        let accounts = accounts()
        let store = store
        store.queue.async {
            let found = store.refresh(accounts: accounts) { done, total in
                DispatchQueue.main.async { MainActor.assumeIsolated { AgentHistoryController.shared.showProgress(done, total) } }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { AgentHistoryController.shared.finished(found) }
            }
        }
    }

    private func showProgress(_ done: Int, _ total: Int) {
        progress = done < total ? (done, total) : nil
        publish()
    }

    private func finished(_ found: [AgentHistoryEntry]) {
        running = false
        progress = nil
        entries = found.filter { $0.updated != nil }.sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }
        publish()
        if again {
            again = false
            refresh()
        }
    }

    /// The paths whose texts hold every word, off the main thread.
    public func search(_ words: String, found: @escaping @MainActor (Set<String>) -> Void) {
        let store = store
        store.queue.async {
            let paths = store.search(words)
            DispatchQueue.main.async { MainActor.assumeIsolated { found(paths) } }
        }
    }

    private func publish() {
        for changed in watchers.values { changed() }
    }

    // MARK: Watching

    /// One stream over the accounts' projects/ folders, a second of latency:
    /// a transcript grows at every message, and one pass per second is plenty.
    private func startWatching() {
        let paths = accounts().filter { $0.provider == .claude }.map { $0.dir + "/projects" }
            .filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext()
        let callback: FSEventStreamCallback = { _, _, _, _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { AgentHistoryController.shared.refresh() } }
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private static func end(_ stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

/// The commands a history entry types in a terminal, with the session kit
/// (docs/adr/0021-cadex-managed-accounts.md: Cadex opens the agent with no
/// prompt; it only types the command).
public enum AgentHistoryLaunch {
    /// "Resume": in the account that owns it, by its id.
    @MainActor
    public static func resume(_ entry: AgentHistoryEntry, kit: SessionKit = .shared) -> String {
        kit.claudeCommand(configDir: configDir(entry.account), arguments: ["--resume", entry.id])
    }

    /// "Continue in another account": by the file's path, with
    /// --fork-session, which is required: without it the other account
    /// writes into the first one's file (test of 2026-11-14; by the id alone
    /// the other account answers "No conversation found").
    @MainActor
    public static func continueIn(_ entry: AgentHistoryEntry, account: AgentAccount, kit: SessionKit = .shared) -> String {
        kit.claudeCommand(configDir: account.isDefault ? nil : account.dir, arguments: ["--resume", entry.path, "--fork-session"])
    }

    /// Where its tab opens: the folder it ran in, else the home folder.
    public static func folder(_ entry: AgentHistoryEntry) -> String {
        FileManager.default.fileExists(atPath: entry.cwd) ? entry.cwd : NSHomeDirectory()
    }

    /// The default account runs with no CLAUDE_CONFIG_DIR.
    @MainActor
    static func configDir(_ account: String) -> String? {
        account == NSHomeDirectory() + "/.claude" || account == AgentsController.shared.homeFolder + "/.claude" ? nil : account
    }
}
