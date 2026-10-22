import CoreServices
import Foundation

/// The agents of every account on this Mac, read once for the whole app,
/// and only while something shows them (the Agents page, its icon's dot,
/// the status bar's Agents item): with nobody watching there is no file
/// watched and no timer (the owner's rule for plan 17, 2026-10-21).
/// Watching is FSEvents on each account's sessions folder, with file events:
/// a folder-only watch missed Claude Code writing in place (proof of
/// concept, 2026-10-21); 6 events in 90 s cost 0.015% of a core.
@MainActor
public final class AgentsController {
    public static let shared = AgentsController()

    public private(set) var accounts: [AgentAccount] = []
    public private(set) var sessions: [AgentSession] = []
    /// Session files that did not read: another Claude Code version.
    public private(set) var unreadable = 0
    /// The session whose subagents show, and those subagents.
    public private(set) var openSession: String?
    public private(set) var subagents: [AgentSubagent] = []
    /// agents.accountNames (folder → name) and agents.hiddenAccounts.
    public var names: [String: String] = [:] { didSet { if names != oldValue { reload(accounts: true) } } }
    public var hidden: Set<String> = [] { didSet { if hidden != oldValue { publish() } } }
    /// The accounts not hidden: Accounts' cards, the usage item.
    public var shownAccounts: [AgentAccount] { accounts.filter { !hidden.contains($0.dir) } }
    /// Every account of every provider (Claude Code and Codex), with the
    /// names given, hidden ones too: the Accounts tab.
    public func everyAccount() -> [AgentAccount] {
        // Kept 10 s: each .claude.json is ~120 KB, and the usage item, its
        // card and Accounts ask on every redraw; reading them each time made
        // the bar stutter while agents worked (owner, 2026-10-21).
        if let kept = keptAccounts, Date().timeIntervalSince(kept.at) < 10, kept.names == names, kept.home == home { return kept.list }
        let list = (AgentAccount.find(home: home) + CodexUsage.accounts(home: home)).map { account in
            guard let name = names[account.dir] else { return account }
            var renamed = AgentAccount(dir: account.dir, name: name, isDefault: account.isDefault)
            renamed.provider = account.provider
            return renamed
        }
        keptAccounts = (list, Date(), names, home)
        return list
    }
    private var keptAccounts: (list: [AgentAccount], at: Date, names: [String: String], home: String)?
    /// agents.sessions: off, nothing is read at all.
    public var isEnabled = true { didSet { if isEnabled != oldValue { restart() } } }
    /// The folder accounts are looked for in (tests use a temporary one).
    /// CADEX_PERF_HOME: `make perf`'s folder of test accounts and sessions.
    var home = ProcessInfo.processInfo.environment["CADEX_PERF_HOME"] ?? NSHomeDirectory()

    private var watchers: [UUID: () -> Void] = [:]
    private var stream: FSEventStreamRef?
    private var watchedPaths: [String] = []
    private var liveness: Timer?

    /// Whether anything is read now: false means no stream and no timer.
    var isRunning: Bool { stream != nil || liveness != nil }

    /// Starts reading for `changed` (now, and on every change); the token stops it.
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

    /// Opens or closes a session's subagents (a click on it in the page).
    public func toggle(_ sessionID: String) {
        openSession = openSession == sessionID ? nil : sessionID
        reload(accounts: false)
    }

    /// How many work and how many wait for an answer: the status item, the dot.
    public var counts: (working: Int, waiting: Int) {
        (sessions.filter { $0.status == .working }.count, sessions.filter { $0.status == .waiting }.count)
    }

    private func restart() {
        stopWatching()
        guard isEnabled, !watchers.isEmpty else {
            accounts = []
            sessions = []
            subagents = []
            publish()
            return
        }
        reload()
        let timer = Timer(timeInterval: 10, repeats: true) { _ in MainActor.assumeIsolated { AgentsController.shared.reload() } }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        liveness = timer
    }

    /// Reads again: the live sessions, the open one's subagents, and the
    /// accounts when `accounts` (at start and on the 10 s check; each
    /// .claude.json is ~120 KB, too much to parse on every session event);
    /// watches the folders that matter now.
    func reload(accounts findAccounts: Bool = true) {
        guard isEnabled, !watchers.isEmpty else { return }
        if findAccounts || accounts.isEmpty {
            accounts = AgentAccount.find(home: home).map { account in
                names[account.dir].map { AgentAccount(dir: account.dir, name: $0, isDefault: account.isDefault) } ?? account
            }
        }
        var all: [AgentSession] = []
        var bad = 0
        for account in accounts {
            let read = AgentSession.read(account)
            all += read.sessions
            bad += read.unreadable
        }
        sessions = all
        unreadable = bad
        if let open = openSession, let session = sessions.first(where: { $0.id == open }) {
            subagents = AgentSubagent.read(session)
        } else {
            openSession = nil
            subagents = []
        }
        var paths = accounts.map { $0.dir + "/sessions" }
        if let open = openSession, let session = sessions.first(where: { $0.id == open }) { paths.append(AgentSubagent.folder(of: session)) }
        watchFolders(paths.filter { FileManager.default.fileExists(atPath: $0) })
        publish()
    }

    func publish() {
        for changed in watchers.values { changed() }
    }

    // MARK: FSEvents

    private func watchFolders(_ paths: [String]) {
        guard paths != watchedPaths || stream == nil else { return }
        if let stream { Self.end(stream) }
        stream = nil
        watchedPaths = paths
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext()
        let callback: FSEventStreamCallback = { _, _, _, _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { AgentsController.shared.reload(accounts: false) } }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func stopWatching() {
        if let stream { Self.end(stream) }
        stream = nil
        watchedPaths = []
        liveness?.invalidate()
        liveness = nil
    }

    private static func end(_ stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
