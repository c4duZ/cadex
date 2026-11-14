import Foundation
import SessionKit

/// What an account's .claude.json says about its login, read only and
/// never written (docs/adr/0021-cadex-managed-accounts.md): whether it has
/// one (`oauthAccount`), the plan ("max", "team") and what changes when
/// another account or organization logs in. No token is read: Cadex never
/// touches the Keychain or the credentials file.
struct AgentAccountLogin: Equatable, Sendable {
    let plan: String?
    /// The account and organization ids: a hidden account comes back when
    /// this changes, never on a window's reset (the owner, 2026-10-21).
    let fingerprint: String

    /// The default account keeps its .claude.json beside ~/.claude, the
    /// others inside their folder.
    static func file(of account: AgentAccount) -> String {
        account.isDefault ? (account.dir as NSString).deletingLastPathComponent + "/.claude.json" : account.dir + "/.claude.json"
    }

    /// Off the main thread: the default .claude.json can be a few MB.
    static func read(_ account: AgentAccount) -> AgentAccountLogin? {
        if account.provider == .codex {
            guard let auth = json(account.dir + "/auth.json") else { return nil }
            return AgentAccountLogin(plan: nil, fingerprint: auth["last_refresh"] as? String ?? "login")
        }
        return FileManager.default.contents(atPath: file(of: account)).flatMap(parse)
    }

    static func parse(_ data: Data) -> AgentAccountLogin? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = object["oauthAccount"] as? [String: Any], !oauth.isEmpty else { return nil }
        let type = oauth["organizationType"] as? String
        let plan = type.map { $0.hasPrefix("claude_") ? String($0.dropFirst(7)) : $0 }
        let ids = [oauth["accountUuid"], oauth["organizationUuid"]].compactMap { $0 as? String }
        return AgentAccountLogin(plan: plan, fingerprint: ids.isEmpty ? "login" : ids.joined(separator: "/"))
    }
}

/// The usage files `cadex statusline` writes from the `rate_limits` Claude
/// Code hands its status line (core/features/agent-tools/statusline.zig):
/// one per account, named by `SessionKit.accountKey`.
enum AgentUsageFile {
    /// CADEX_USAGE_DIR (tests, perf), else Cadex's folder in Application Support.
    static func folder(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let dir = environment["CADEX_USAGE_DIR"], !dir.isEmpty { return dir }
        return FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Application Support/Cadex/usage"
    }

    static func path(of account: AgentAccount, in folder: String) -> String {
        folder + "/" + SessionKit.accountKey(account.dir) + ".json"
    }
}

/// How much of the plan an account used: the 5 hour session and the week
/// (and the week's Sonnet share when the plan has one), each with when it
/// resets (docs/spec/agents.md, Accounts).
public struct AgentUsage: Equatable, Sendable {
    public struct Window: Equatable, Sendable {
        /// 0 to 100.
        public let percent: Double
        public let resets: Date?
    }

    public let session: Window?
    public let week: Window?
    public let sonnetWeek: Window?

    /// An account's usage file: the numbers and when a session wrote them.
    /// A window that reset since then shows 0%. Missing fields are
    /// skipped; a broken file is nil.
    static func parseFile(_ data: Data, now: Date = Date()) -> (AgentUsage, Date)? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let limits = object["rate_limits"] as? [String: Any] else { return nil }
        let at = (object["at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? now
        func window(_ key: String) -> Window? {
            guard let part = limits[key] as? [String: Any], let percent = (part["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
            let resets = date(part["resets_at"])
            if let resets, resets <= now { return Window(percent: 0, resets: nil) }
            return Window(percent: percent, resets: resets)
        }
        let usage = AgentUsage(session: window("five_hour"), week: window("seven_day"), sonnetWeek: window("seven_day_sonnet"))
        return usage.session == nil && usage.week == nil ? nil : (usage, at)
    }

    /// Seconds since 1970 (milliseconds when that large) or ISO 8601 text:
    /// the field's form is Claude Code's to change.
    static func date(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let seconds = number.doubleValue > 1e12 ? number.doubleValue / 1000 : number.doubleValue
            return Date(timeIntervalSince1970: seconds)
        }
        guard let text = value as? String else { return nil }
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return full.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// What an account's card and the usage item show.
public enum AgentUsageState: Equatable, Sendable {
    case loading
    /// The numbers, and when a session wrote them.
    case ready(AgentUsage, Date)
    /// A session of this account failed to authenticate: run claude to log in.
    case expired
    /// No login in the account's .claude.json.
    case noLogin
    /// Logged in, but no session opened by Cadex has told the usage yet.
    case noUsage

    public var usage: AgentUsage? {
        if case .ready(let usage, _) = self { return usage }
        return nil
    }
}

/// Numbers older than this are shown dimmed, with their age.
let agentUsageOld: TimeInterval = 600
