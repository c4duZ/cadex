import Foundation

/// The shared configuration (docs/spec/agents.md, Contas gerenciadas;
/// docs/adr/0021-cadex-managed-accounts.md): an account follows the default
/// one (~/.claude) through links to everything at the source's top level
/// except the account's own state. A deny list, not an allow list: what a
/// tool installs there (GSD's gsd-core/, package.json) keeps working.
public enum AgentConfigShare {
    /// The account's own state, never linked: two writers in one projects/
    /// lose messages, one account's 30-day cleanup would delete the other's
    /// sessions, and .credentials.json is a login (plan 18; names seen in the
    /// owner's ~/.claude and ~/.claude-bkdg, Claude Code 2.1.325, 2026-11-14).
    static let state: Set<String> = [
        ".claude.json", ".credentials.json", "projects", "sessions", "history.jsonl", "jobs", "daemon", "state",
        "file-history", "paste-cache", "shell-snapshots", "cache", "backups", "downloads", "feedback", "session-env",
        "stats-cache.json", "tasks", "todos", "telemetry", "statsig", "ide", "debug", "chrome", ".DS_Store",
    ]
    /// Families of state: the daemon's files, the last-run marks, and the
    /// organization's own policy and remote settings (another account may
    /// be another organization).
    static let statePrefixes = ["daemon-", "daemon.", ".last-", "policy-limits", "remote-settings"]
    static let stateSuffixes = ["-cache.json"]

    public static func isAccountState(_ name: String) -> Bool {
        state.contains(name) || statePrefixes.contains { name.hasPrefix($0) } || stateSuffixes.contains { name.hasSuffix($0) }
    }

    /// The source's top-level names an account may link, sorted.
    public static func sharable(source: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: source)) ?? []).filter { !isAccountState($0) }.sorted()
    }

    public enum Item: Equatable, Sendable {
        /// A link to the source's item.
        case linked
        /// Nothing there yet.
        case missing
        /// A real file or folder: the account's own copy, which does not follow.
        case own
        /// A link somewhere else: the user's, left alone.
        case elsewhere
    }

    public static func item(_ name: String, account: String, source: String) -> Item {
        let path = account + "/" + name
        if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) {
            return target == source + "/" + name ? .linked : .elsewhere
        }
        return FileManager.default.fileExists(atPath: path) ? .own : .missing
    }

    /// Whether an account follows the default one: it was made by Cadex or
    /// has at least one link into the source.
    public static func follows(account: String, source: String, managed: Bool) -> Bool {
        managed || sharable(source: source).contains { item($0, account: account, source: source) == .linked }
    }

    /// What sharing does: the links to make and, when `replacing` (an
    /// existing account that opts in), the real items that go to the trash
    /// first. Without `replacing` (a sync), real items are own copies and stay.
    public struct Plan: Equatable, Sendable {
        public var link: [String] = []
        public var trash: [String] = []
    }

    public static func plan(account: String, source: String, replacing: Bool) -> Plan {
        var plan = Plan()
        for name in sharable(source: source) {
            switch item(name, account: account, source: source) {
            case .missing: plan.link.append(name)
            case .own where replacing:
                plan.trash.append(name)
                plan.link.append(name)
            default: break
            }
        }
        return plan
    }

    /// Applies a plan: the trash first (never a delete), then the links. A
    /// link into the source whose item is gone is removed.
    public static func apply(_ plan: Plan, account: String, source: String, trash: (String) throws -> Void) throws {
        let fm = FileManager.default
        for name in plan.trash { try trash(account + "/" + name) }
        for name in plan.link { try fm.createSymbolicLink(atPath: account + "/" + name, withDestinationPath: source + "/" + name) }
        for name in (try? fm.contentsOfDirectory(atPath: account)) ?? [] {
            let path = account + "/" + name
            guard let target = try? fm.destinationOfSymbolicLink(atPath: path), target.hasPrefix(source + "/"),
                  !fm.fileExists(atPath: target) else { continue }
            try? fm.removeItem(atPath: path)
        }
    }

    /// "Use own copy": the link becomes a copy of what it pointed to, which
    /// stops following the source.
    public static func ownCopy(_ name: String, account: String, source: String) throws {
        guard item(name, account: account, source: source) == .linked else { return }
        let path = account + "/" + name
        try FileManager.default.removeItem(atPath: path)
        try FileManager.default.copyItem(atPath: source + "/" + name, toPath: path)
    }

    /// "Follow the default account again": the copy goes to the trash and
    /// the link comes back.
    public static func follow(_ name: String, account: String, source: String, trash: (String) throws -> Void) throws {
        guard item(name, account: account, source: source) == .own, !isAccountState(name),
              FileManager.default.fileExists(atPath: source + "/" + name) else { return }
        try trash(account + "/" + name)
        try FileManager.default.createSymbolicLink(atPath: account + "/" + name, withDestinationPath: source + "/" + name)
    }
}

/// Accounts Cadex makes, in its own folder with a short path (sockets have
/// a path limit). The login is Claude Code's own (/login in a tab): Cadex
/// never sees it. Existing accounts stay where they are: on the Mac the
/// login is tied to the folder's path, and moving logs out.
public enum AgentManagedAccounts {
    public static func folder(home: String) -> String {
        home + "/Library/Application Support/Cadex/accounts"
    }

    public static func isManaged(_ dir: String, home: String) -> Bool {
        dir.hasPrefix(folder(home: home) + "/")
    }

    /// The managed accounts' folders, by name, logged in or not.
    public static func all(home: String) -> [String] {
        let root = folder(home: home)
        return ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []).filter { !$0.hasPrefix(".") }.sorted().map { root + "/" + $0 }
    }

    /// A folder name from what the user typed: lowercase letters, digits and
    /// "-", at most 40; nil when nothing is left.
    public static func folderName(for name: String) -> String? {
        let ascii = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var out = ""
        for scalar in ascii.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII { out.unicodeScalars.append(scalar) }
            else if !out.isEmpty, !out.hasSuffix("-") { out += "-" }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? nil : String(out.prefix(40))
    }

    public enum Failure: Error, Equatable {
        case badName
        case taken(String)
    }

    /// Makes the account's folder with the shared configuration in it.
    public static func create(name: String, home: String) throws -> String {
        guard let folderName = folderName(for: name) else { throw Failure.badName }
        let dir = folder(home: home) + "/" + folderName
        guard !FileManager.default.fileExists(atPath: dir) else { throw Failure.taken(dir) }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let source = home + "/.claude"
        try AgentConfigShare.apply(AgentConfigShare.plan(account: dir, source: source, replacing: false),
                                   account: dir, source: source, trash: { _ in })
        return dir
    }

    /// The system's trash, so nothing is ever deleted for good.
    public static func moveToTrash(_ path: String) throws {
        try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
    }
}
