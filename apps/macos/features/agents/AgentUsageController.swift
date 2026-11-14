import AppKit
import Foundation

/// Every account's plan usage, for the whole app, read only while something
/// shows it (Accounts, the usage item) (docs/spec/agents.md, Accounts).
/// The numbers come from the files `cadex statusline` writes in the
/// sessions Cadex opens (docs/adr/0021-cadex-managed-accounts.md): no
/// token, no Keychain, no request. The usage folder is watched while
/// someone looks; a minute's tick ages the numbers and zeroes windows that
/// reset; the logins (.claude.json) are read at the start and every 5 min.
@MainActor
public final class AgentUsageController {
    public static let shared = AgentUsageController()

    public internal(set) var states: [String: AgentUsageState] = [:]
    /// The plan each account's .claude.json names ("max", "team"), by folder.
    public internal(set) var plans: [String: String] = [:]
    /// agents.accounts: off, no file is read or watched.
    public var isEnabled = true { didSet { if isEnabled != oldValue { restart() } } }
    /// The accounts to read: the shown ones, as AgentsController names them.
    var accounts: () -> [AgentAccount] = {
        let agents = AgentsController.shared
        return agents.everyAccount().filter { !agents.hidden.contains($0.dir) }
    }
    /// Where `cadex statusline` writes (AgentUsageFile).
    var folder = AgentUsageFile.folder()
    /// When a session of each account failed to authenticate, by folder.
    public internal(set) var expiredSince: [String: Date] = [:]

    /// An account not worth a line: no login, or a login out for more than
    /// a day (the owner, 2026-10-21: a short one is a pause, a long one an
    /// account left aside).
    public func isStale(_ dir: String, now: Date = Date()) -> Bool {
        switch states[dir] {
        case .noLogin: return true
        case .expired: return (expiredSince[dir] ?? .distantPast) < now.addingTimeInterval(-86_400)
        default: return false
        }
    }

    /// The accounts the card, the item and Accounts list: shown and in use.
    public func visibleAccounts() -> [AgentAccount] { accounts().filter { !isStale($0.dir) } }

    /// The hidden accounts' login when they were hidden (agents.hiddenLogins).
    public var hiddenLogins: [String: String] = [:]
    /// A hidden account got another login: the app shows it.
    public var onLoginChanged: ((String) -> Void)?

    /// The login now, for hiding an account (off the main thread).
    public func fingerprint(_ account: AgentAccount) async -> String {
        await Task.detached { AgentAccountLogin.read(account)?.fingerprint ?? "none" }.value
    }

    /// A session of the account stopped on "authentication_failed"
    /// (AgentStop): the card asks to log in until a later session works.
    public func loginFailed(_ dir: String, at: Date = Date()) {
        expiredSince[dir] = at
        states[dir] = .expired
        publish()
    }

    /// A login kept before plan 18 was the token's expiry from the Keychain
    /// (digits): it would differ from any oauthAccount fingerprint and bring
    /// every hidden account back after the update, so it is ignored.
    static func isLegacy(_ fingerprint: String) -> Bool {
        !fingerprint.isEmpty && fingerprint.allSatisfy(\.isNumber)
    }

    static let every: TimeInterval = 60
    static let loginsEvery: TimeInterval = 300

    private var watchers: [UUID: () -> Void] = [:]
    private var timer: Timer?
    private var source: DispatchSourceFileSystemObject?
    private var logins: [String: AgentAccountLogin?] = [:]
    private var codexReads: [String: CodexUsage.Reading?] = [:]
    private var loginsRead = Date.distantPast

    var isRunning: Bool { timer != nil }

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

    /// agents.refresh-usage: read the files and the logins now.
    public func refreshNow() {
        loginsRead = .distantPast
        tick()
    }

    private func restart() {
        timer?.invalidate()
        timer = nil
        source?.cancel()
        source = nil
        guard isEnabled, !watchers.isEmpty else { return publish() }
        let timer = Timer(timeInterval: Self.every, repeats: true) { _ in MainActor.assumeIsolated { AgentUsageController.shared.tick() } }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        watchFolder()
        tick()
    }

    /// The folder's own events: `cadex statusline` renames each file into
    /// place, which the folder sees. One descriptor for every account.
    private func watchFolder() {
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let fd = open(folder, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { AgentUsageController.shared.tick() } }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func tick() {
        guard isEnabled, !watchers.isEmpty else { return }
        let accounts = accounts()
        if Date().timeIntervalSince(loginsRead) >= Self.loginsEvery {
            loginsRead = Date()
            Task { await readLogins(accounts) }
        }
        for account in accounts { read(account) }
        publish()
    }

    /// The logins and Codex's logs, off the main thread (both can be a few
    /// MB); a hidden account whose login moved comes back.
    private func readLogins(_ accounts: [AgentAccount]) async {
        let everyone = AgentsController.shared.everyAccount().filter { hiddenLogins[$0.dir] != nil } + accounts
        let read = await Task.detached {
            everyone.map { account in
                (account.dir, AgentAccountLogin.read(account), account.provider == .codex ? CodexUsage.read(account) : nil)
            }
        }.value
        for (dir, login, codex) in read {
            logins[dir] = login
            codexReads[dir] = codex
            if let plan = login?.plan ?? codex?.plan { plans[dir] = plan }
            if let before = hiddenLogins[dir], !Self.isLegacy(before), let now = login?.fingerprint, now != before { onLoginChanged?(dir) }
        }
        tick()
    }

    /// An account's state from what is known: a login not read yet stays
    /// loading; Codex shows what its logs said at the last reading.
    private func read(_ account: AgentAccount) {
        guard let known = logins[account.dir] else { return states[account.dir] = states[account.dir] ?? .loading }
        if account.provider == .codex {
            guard let reading = codexReads[account.dir] ?? nil else { return states[account.dir] = .noLogin }
            return states[account.dir] = .ready(reading.usage, reading.at)
        }
        guard known != nil else { return states[account.dir] = .noLogin }
        let file = FileManager.default.contents(atPath: AgentUsageFile.path(of: account, in: folder)).flatMap { AgentUsage.parseFile($0) }
        if let since = expiredSince[account.dir], (file?.1 ?? .distantPast) <= since { return states[account.dir] = .expired }
        expiredSince[account.dir] = nil
        states[account.dir] = file.map { .ready($0.0, $0.1) } ?? .noUsage
    }

    private func publish() {
        for changed in watchers.values { changed() }
    }
}
