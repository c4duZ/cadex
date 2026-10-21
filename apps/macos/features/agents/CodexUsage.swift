import Foundation

/// Codex accounts and their usage, from the files the Codex CLI keeps: no
/// request and no token used (docs/spec/agents.md, Accounts). Each session
/// log (sessions/YYYY/MM/DD/rollout-*.jsonl) carries the plan's limits in
/// its token_count events: "primary" is the 5 hour window, "secondary" the
/// week, each with the share used and when it resets (seen 2026-10-21).
/// The numbers are those of Codex's last use: a window that reset since
/// reads 0%.
enum CodexUsage {
    /// ~/.codex and each ~/.codex-* with an auth.json (a CODEX_HOME of its
    /// own), named by the login's email.
    static func accounts(home: String) -> [AgentAccount] {
        let fm = FileManager.default
        let names = ["." + "codex"] + ((try? fm.contentsOfDirectory(atPath: home)) ?? []).filter { $0.hasPrefix(".codex-") }.sorted()
        return names.compactMap { name in
            let dir = home + "/" + name
            guard fm.fileExists(atPath: dir + "/auth.json") else { return nil }
            var account = AgentAccount(dir: dir, name: email(dir) ?? "ChatGPT", isDefault: name == ".codex")
            account.provider = .codex
            return account
        }
    }

    /// The login's email, from the id token's payload (read, not checked:
    /// it only names the account).
    static func email(_ dir: String) -> String? {
        guard let auth = json(dir + "/auth.json"), let tokens = auth["tokens"] as? [String: Any],
              let token = tokens["id_token"] as? String else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return claims["email"] as? String
    }

    /// The newest session log: the latest day folder first, then its newest file.
    static func newestLog(_ dir: String) -> String? {
        let fm = FileManager.default
        func entries(_ path: String) -> [String] { ((try? fm.contentsOfDirectory(atPath: path)) ?? []).filter { !$0.hasPrefix(".") }.sorted(by: >) }
        let root = dir + "/sessions"
        for year in entries(root) {
            for month in entries(root + "/" + year) {
                for day in entries(root + "/\(year)/\(month)") {
                    let folder = root + "/\(year)/\(month)/\(day)"
                    let logs = entries(folder).filter { $0.hasSuffix(".jsonl") }.map { folder + "/" + $0 }
                    let newest = logs.max { modified($0) < modified($1) }
                    if let newest { return newest }
                }
            }
        }
        return nil
    }

    static func modified(_ path: String) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date ?? .distantPast
    }

    /// The last limits in the end of the newest log (256 KB, once per reading),
    /// the plan, and when they were written.
    static func read(_ account: AgentAccount, now: Date = Date()) -> (usage: AgentUsage, plan: String?, at: Date)? {
        guard let log = newestLog(account.dir), let handle = FileHandle(forReadingAtPath: log) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 262_144 ? size - 262_144 : 0)
        let text = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let limits = find("rate_limits", in: object) else { continue }
            func window(_ key: String) -> AgentUsage.Window? {
                guard let part = limits[key] as? [String: Any], let used = (part["used_percent"] as? NSNumber)?.doubleValue else { return nil }
                let resets = (part["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
                // Reset since Codex last ran: nothing used in this window yet.
                if let resets, resets < now { return .init(percent: 0, resets: nil) }
                return .init(percent: used, resets: resets)
            }
            let usage = AgentUsage(session: window("primary"), week: window("secondary"), sonnetWeek: nil)
            guard usage.session != nil || usage.week != nil else { continue }
            return (usage, limits["plan_type"] as? String, modified(log))
        }
        return nil
    }

    /// The first value under `key` anywhere in the event (it sits in its payload).
    static func find(_ key: String, in object: Any) -> [String: Any]? {
        if let dict = object as? [String: Any] {
            if let found = dict[key] as? [String: Any] { return found }
            for value in dict.values { if let found = find(key, in: value) { return found } }
        } else if let list = object as? [Any] {
            for value in list { if let found = find(key, in: value) { return found } }
        }
        return nil
    }
}
