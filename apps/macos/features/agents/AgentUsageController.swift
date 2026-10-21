import AppKit
import Foundation

/// Every account's plan usage, read for the whole app and only while
/// something shows it (Accounts, the usage item) with the app active
/// (docs/spec/agents.md, Accounts). One request per account, every 5 min;
/// a reading younger than 60 s is not repeated; errors wait 5, 10, 20 and
/// then 60 min; a 429 waits what the service asks, or 5 min. An expired
/// login makes no request. Cadex says it is Cadex (ADR 0019).
@MainActor
public final class AgentUsageController {
    public static let shared = AgentUsageController()

    public internal(set) var states: [String: AgentUsageState] = [:]
    /// The plan each login says ("max", "team"), by account folder.
    public internal(set) var plans: [String: String] = [:]
    /// agents.accounts: off, no login is read and no request is made.
    public var isEnabled = true { didSet { if isEnabled != oldValue { restart() } } }
    /// The accounts to read: the shown ones, as AgentsController names them.
    var accounts: () -> [AgentAccount] = {
        let agents = AgentsController.shared
        return agents.everyAccount().filter { !agents.hidden.contains($0.dir) }
    }
    /// When each expired login ran out, by account folder.
    public internal(set) var expiredSince: [String: Date] = [:]

    /// An account not worth a line: no login, or a login out for more than
    /// a day (Claude Code renews it while the account is used, so a short
    /// one is a pause, a long one an account left aside; the owner,
    /// 2026-10-21).
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
    /// A hidden account logged in again (or was used): the app shows it.
    public var onLoginChanged: ((String) -> Void)?
    private var lastLoginCheck = Date.distantPast

    /// The login now, for hiding an account (off the main thread).
    public func fingerprint(_ account: AgentAccount) async -> String {
        await Task.detached { AgentLogin.fingerprint(account) }.value
    }

    /// Every 5 min while something reads: has a hidden account's login moved?
    private func checkHidden() {
        guard Date().timeIntervalSince(lastLoginCheck) >= Self.every, !hiddenLogins.isEmpty else { return }
        lastLoginCheck = Date()
        let hidden = AgentsController.shared.everyAccount().filter { hiddenLogins[$0.dir] != nil }
        let kept = hiddenLogins
        Task {
            for account in hidden {
                let now = await fingerprint(account)
                if let before = kept[account.dir], now != before, now != "none" { onLoginChanged?(account.dir) }
            }
        }
    }

    var fetch: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }

    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let every: TimeInterval = 300
    static let fresh: TimeInterval = 60
    static let waits: [TimeInterval] = [300, 600, 1200, 3600]

    private var watchers: [UUID: () -> Void] = [:]
    private var timer: Timer?
    private var lastRead: [String: Date] = [:]
    private var nextTry: [String: Date] = [:]
    private var failures: [String: Int] = [:]
    private var inFlight: Set<String> = []

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

    /// agents.refresh-usage: read now, past the 60 s and the error waits
    /// (not past a 429's).
    public func refreshNow() {
        for account in accounts() where failures[account.dir] != -1 {
            lastRead[account.dir] = nil
            nextTry[account.dir] = nil
        }
        tick()
    }

    private func restart() {
        timer?.invalidate()
        timer = nil
        guard isEnabled, !watchers.isEmpty else { return publish() }
        let timer = Timer(timeInterval: 30, repeats: true) { _ in MainActor.assumeIsolated { AgentUsageController.shared.tick() } }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    /// Every 30 s it looks; an account is read when its 5 min (or its wait)
    /// is up, and only with Cadex active: in the background nobody reads it.
    func tick() {
        guard isEnabled, !watchers.isEmpty, NSApp?.isActive != false else { return }
        let now = Date()
        for account in accounts() where !inFlight.contains(account.dir) {
            if let wait = nextTry[account.dir], wait > now { continue }
            if let last = lastRead[account.dir], now.timeIntervalSince(last) < (states[account.dir] == nil ? Self.fresh : Self.every) { continue }
            if states[account.dir] == nil { states[account.dir] = .loading }
            inFlight.insert(account.dir)
            Task { await self.read(account) }
        }
        checkHidden()
        publish()
    }

    private func read(_ account: AgentAccount) async {
        defer {
            inFlight.remove(account.dir)
            publish()
        }
        lastRead[account.dir] = Date()
        if account.provider == .codex { return await readCodex(account) }
        let login = await Task.detached { AgentLogin.read(account) }.value
        guard let login else { return states[account.dir] = .noLogin }
        if let plan = login.plan { plans[account.dir] = plan }
        if login.isExpired {
            expiredSince[account.dir] = login.expires
            return states[account.dir] = .expired
        }
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 10)
        request.setValue("Bearer " + login.token, forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("Cadex/" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"), forHTTPHeaderField: "User-Agent")
        let result = try? await fetch(request)
        let code = (result?.1 as? HTTPURLResponse)?.statusCode ?? 0
        let last = states[account.dir]?.usage
        switch code {
        case 200 where result.flatMap({ AgentUsage.parse($0.0) }) != nil:
            states[account.dir] = .ready(AgentUsage.parse(result!.0)!, Date())
            failures[account.dir] = 0
            nextTry[account.dir] = nil
        case 401, 403:
            states[account.dir] = .expired
        case 429:
            let asked = (result?.1 as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            nextTry[account.dir] = Date().addingTimeInterval(asked ?? Self.waits[0])
            // -1 marks a wait the service asked for: Refresh does not skip it.
            failures[account.dir] = -1
            states[account.dir] = .failed(last, lastGood(account))
        default:
            let count = max(failures[account.dir] ?? 0, 0) + 1
            failures[account.dir] = count
            nextTry[account.dir] = Date().addingTimeInterval(Self.waits[min(count, Self.waits.count) - 1])
            states[account.dir] = .failed(last, lastGood(account))
        }
    }

    /// Codex: the limits its own logs carry, no request (CodexUsage).
    private func readCodex(_ account: AgentAccount) async {
        let read = await Task.detached { CodexUsage.read(account) }.value
        guard let read else { return states[account.dir] = .noLogin }
        if let plan = read.plan { plans[account.dir] = plan }
        states[account.dir] = .ready(read.usage, read.at)
    }

    private func lastGood(_ account: AgentAccount) -> Date? {
        switch states[account.dir] {
        case .ready(_, let at): at
        case .failed(_, let at): at
        default: nil
        }
    }

    private func publish() {
        for changed in watchers.values { changed() }
    }
}
