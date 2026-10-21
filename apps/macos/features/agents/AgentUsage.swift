import CryptoKit
import Foundation

/// An account's login as Claude Code keeps it: the Keychain item named
/// after the folder ("Claude Code-credentials", or "-" plus the first 8 hex
/// of the SHA-256 of its path), else the folder's .credentials.json. Read
/// for each request and never kept, refreshed or written (ADR 0019).
struct AgentLogin: Equatable, Sendable {
    let token: String
    let expires: Date?
    /// "max", "team", "pro".
    let plan: String?

    var isExpired: Bool { expires.map { $0 < Date() } ?? false }

    static func service(for account: AgentAccount) -> String {
        if account.isDefault { return "Claude Code-credentials" }
        let hash = SHA256.hash(data: Data(account.dir.utf8)).map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-" + hash.prefix(8)
    }

    /// Off the main thread: the Keychain answers through /usr/bin/security,
    /// which reads Claude Code's items without asking (the proof of concept,
    /// 2026-10-21); an app's own Keychain call would ask once per account.
    static func read(_ account: AgentAccount) -> AgentLogin? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service(for: account), "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        var data = Data()
        if (try? process.run()) != nil {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
        }
        if let login = parse(data) { return login }
        return FileManager.default.contents(atPath: account.dir + "/.credentials.json").flatMap(parse)
    }

    /// What changes when the account logs in again or Claude Code renews
    /// its token by use: a hidden account comes back on a change of this,
    /// never on a window's reset (the owner, 2026-10-21). "none" without a login.
    static func fingerprint(_ account: AgentAccount) -> String {
        if account.provider == .codex {
            let auth = json(account.dir + "/auth.json")
            return auth?["last_refresh"] as? String ?? (auth == nil ? "none" : "login")
        }
        guard let login = read(account) else { return "none" }
        return login.expires.map { String(Int($0.timeIntervalSince1970)) } ?? "login"
    }

    static func parse(_ data: Data) -> AgentLogin? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any], let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        let expires = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return AgentLogin(token: token, expires: expires, plan: oauth["subscriptionType"] as? String)
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

    static func parse(_ data: Data) -> AgentUsage? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func window(_ key: String) -> Window? {
            guard let part = object[key] as? [String: Any], let percent = (part["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return Window(percent: percent, resets: (part["resets_at"] as? String).flatMap(date))
        }
        let usage = AgentUsage(session: window("five_hour"), week: window("seven_day"), sonnetWeek: window("seven_day_sonnet"))
        return usage.session == nil && usage.week == nil ? nil : usage
    }

    static func date(_ text: String) -> Date? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return full.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// What an account's card and the usage item show.
public enum AgentUsageState: Equatable, Sendable {
    case loading
    /// The numbers, and when they were read.
    case ready(AgentUsage, Date)
    /// The login ran out: run claude with that account to renew it.
    case expired
    /// No login found for the account.
    case noLogin
    /// The last reading failed; the last good numbers, if any, stay shown.
    case failed(AgentUsage?, Date?)

    public var usage: AgentUsage? {
        switch self {
        case .ready(let usage, _): usage
        case .failed(let usage, _): usage
        default: nil
        }
    }
}
