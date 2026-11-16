import Foundation
import Icons

/// A Claude Code configuration folder: ~/.claude or one of ~/.claude-*,
/// each with its own login (docs/spec/agents.md, Accounts).
/// Whose account it is: a Claude Code folder or a Codex one.
public enum AgentProvider: String, Equatable, Sendable {
    case claude
    case codex
}

public struct AgentAccount: Equatable, Sendable {
    public let dir: String
    /// The organization's name, or the folder's suffix when the name is
    /// only "x's Organization" ("bhband" for ~/.claude-bhband).
    public let name: String
    public let isDefault: Bool
    public var provider: AgentProvider = .claude

    /// Every account folder in `home`: ~/.claude when it exists, then each
    /// ~/.claude-* holding a .claude.json, by name, then the accounts Cadex
    /// made (AgentManagedAccounts) once Claude Code wrote their .claude.json.
    /// Reading stops at what is there; nothing is asked of the user (the
    /// proof of concept, 2026-10-21).
    public static func find(home: String) -> [AgentAccount] {
        let fm = FileManager.default
        var accounts: [AgentAccount] = []
        let base = home + "/.claude"
        if fm.fileExists(atPath: base) {
            accounts.append(AgentAccount(dir: base, name: label(json(home + "/.claude.json"), fallback: "default"), isDefault: true))
        }
        let names = ((try? fm.contentsOfDirectory(atPath: home)) ?? []).filter { $0.hasPrefix(".claude-") }.sorted()
        for name in names {
            let dir = home + "/" + name
            guard fm.fileExists(atPath: dir + "/.claude.json") else { continue }
            accounts.append(AgentAccount(dir: dir, name: label(json(dir + "/.claude.json"), fallback: String(name.dropFirst(8))), isDefault: false))
        }
        for dir in AgentManagedAccounts.all(home: home) where fm.fileExists(atPath: dir + "/.claude.json") {
            accounts.append(AgentAccount(dir: dir, name: label(json(dir + "/.claude.json"), fallback: (dir as NSString).lastPathComponent), isDefault: false))
        }
        return distinct(accounts)
    }

    /// Two accounts of the same organization get the folder after the name,
    /// "fba. + BKDG · bkdg" (the owner's ~/.claude and ~/.claude-bkdg, 2026-10-21).
    static func distinct(_ accounts: [AgentAccount]) -> [AgentAccount] {
        accounts.map { account in
            guard accounts.filter({ $0.name == account.name }).count > 1 else { return account }
            let last = (account.dir as NSString).lastPathComponent
            let folder = account.isDefault ? "default" : last.hasPrefix(".claude-") ? String(last.dropFirst(8)) : last
            return AgentAccount(dir: account.dir, name: "\(account.name) · \(folder)", isDefault: account.isDefault)
        }
    }

    static func label(_ file: [String: Any]?, fallback: String) -> String {
        let org = (file?["oauthAccount"] as? [String: Any])?["organizationName"] as? String ?? ""
        return org.isEmpty || org.hasSuffix("'s Organization") ? fallback : org
    }
}

/// One live Claude Code session: its registry file in the account's
/// sessions folder, kept by Claude Code while it runs.
public struct AgentSession: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case working
        case waiting
        case other(String)
    }

    public let account: AgentAccount
    public let pid: Int32
    public let id: String
    public let name: String
    public let cwd: String
    public let status: Status
    /// Since when it is in that status.
    public let since: Date
    /// A background session (agent view, `claude --bg`): its job id, which
    /// `claude attach <job>` opens; nil for one running in a terminal.
    public var job: String? = nil
    /// What a background session waits for ("permission prompt").
    public var waitingFor: String? = nil
    /// A session on another machine (plan 23, "Run on"): the machine's name;
    /// nil for one on this Mac.
    public var machine: String? = nil

    /// The sessions of `account` whose process is alive. A file that does
    /// not read (another Claude Code version) is skipped, never fatal; the
    /// count of those comes back for the page's note.
    public static func read(_ account: AgentAccount, alive: (Int32) -> Bool = AgentSession.isAlive) -> (sessions: [AgentSession], unreadable: Int) {
        let dir = account.dir + "/sessions"
        var sessions: [AgentSession] = []
        var unreadable = 0
        for file in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where file.hasSuffix(".json") {
            guard let object = json(dir + "/" + file) else { unreadable += 1; continue }
            guard let session = parse(object, account: account) else { unreadable += 1; continue }
            if alive(session.pid) { sessions.append(session) }
        }
        return (sessions.sorted { $0.since > $1.since }, unreadable)
    }

    static func parse(_ object: [String: Any], account: AgentAccount) -> AgentSession? {
        guard let pid = (object["pid"] as? NSNumber)?.int32Value, let id = object["sessionId"] as? String,
              let cwd = object["cwd"] as? String else { return nil }
        // busy works; idle, waiting and shell all wait for you. waiting is a
        // prompt such as a permission (the ai-usagebar audit); shell is what
        // a turn that just ended reads (seen live, 2026-10-21).
        let status: Status = switch object["status"] as? String ?? "" {
        case "busy": .working
        case "idle", "waiting", "shell": .waiting
        case let other: .other(other)
        }
        let millis = (object["statusUpdatedAt"] as? NSNumber)?.doubleValue ?? (object["startedAt"] as? NSNumber)?.doubleValue ?? 0
        return AgentSession(account: account, pid: pid, id: id, name: object["name"] as? String ?? (cwd as NSString).lastPathComponent,
                            cwd: cwd, status: status, since: Date(timeIntervalSince1970: millis / 1000))
    }

    /// A process that ended leaves its file behind: kill with signal 0
    /// says whether it is still there.
    public static func isAlive(_ pid: Int32) -> Bool { pid > 0 && kill(pid, 0) == 0 }
}

/// The repository a session works in, for the page's groups: the folder
/// holding .git above its cwd (a worktree's .git file counts), and the
/// branch read from HEAD. Plain file reads, no git run.
public struct AgentProject: Equatable, Sendable {
    public let root: String
    public let name: String
    public let branch: String?

    public static func of(_ cwd: String) -> AgentProject {
        let fm = FileManager.default
        var dir = cwd
        while !dir.isEmpty, dir != "/" {
            let git = dir + "/.git"
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: git, isDirectory: &isDir) {
                return AgentProject(root: dir, name: (dir as NSString).lastPathComponent, branch: branch(git: git, isDir: isDir.boolValue))
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return AgentProject(root: cwd, name: (cwd as NSString).lastPathComponent, branch: nil)
    }

    static func branch(git: String, isDir: Bool) -> String? {
        var folder = git
        if !isDir {
            // A worktree: ".git" is a file pointing at its folder.
            guard let text = try? String(contentsOfFile: git, encoding: .utf8), text.hasPrefix("gitdir: ") else { return nil }
            let path = text.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines)
            folder = path.hasPrefix("/") ? path : ((git as NSString).deletingLastPathComponent as NSString).appendingPathComponent(path)
        }
        guard let head = try? String(contentsOfFile: folder + "/HEAD", encoding: .utf8) else { return nil }
        let line = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ref: refs/heads/") { return String(line.dropFirst(16)) }
        return String(line.prefix(7))
    }
}

/// A subagent a session started for a task, from the description file
/// Claude Code keeps beside its log.
public struct AgentSubagent: Equatable, Sendable {
    public let id: String
    public let type: String
    public let description: String
    public let lastWrite: Date
    /// The description file's `finished`: true once the subagent is done,
    /// missing while it runs (Claude Code 2.1.325, 2026-11-14). nil also for
    /// an older file without the field (`knowsFinished` false).
    public var finished: Bool? = nil
    /// Whether this Claude Code writes `finished` (its files carry
    /// `spawnDepth` beside it); an older one gets the 30 s estimate.
    public var knowsFinished = false
    /// The folder its files are in: its session's, or, for a session
    /// continued from another account's conversation, the origin's, where
    /// the subagents from before the copy stayed (test of 2026-11-14).
    public var dir = ""

    /// Running: not finished, on a Claude Code that says so; on an older
    /// one, the log changed in the last 30 s. A long command left the log
    /// silent for 12 s while the subagent worked (test loop, 2026-11-14), so
    /// the estimate alone called it done too soon. No write in 10 min ends
    /// it either way: a subagent killed with its session never says done.
    public var isRunning: Bool {
        let quiet = Date().timeIntervalSince(lastWrite)
        guard knowsFinished else { return quiet < 30 }
        return finished != true && quiet < 600
    }

    /// The folder Claude Code keeps a session's subagents in.
    public static func folder(of session: AgentSession) -> String {
        "\(AgentProjectFolder.path(for: session.cwd, in: session.account))/\(session.id)/subagents"
    }

    /// The newest 10 first: the session's own and, given `origins` (the
    /// origin conversations' subagents folders), those from before a copy.
    public static func read(_ session: AgentSession, origins: [String] = []) -> [AgentSubagent] {
        let found = ([folder(of: session)] + origins).flatMap(read(folder:))
        return Array(found.sorted { $0.lastWrite > $1.lastWrite }.prefix(10))
    }

    /// The subagents folders of the conversation `session` was continued
    /// from, if any: the origin's id from the first lines of its transcript
    /// (AgentHistoryReader's rule), its transcript looked up in every account.
    public static func origins(of session: AgentSession, accounts: [AgentAccount]) -> [String] {
        let transcript = "\(AgentProjectFolder.path(for: session.cwd, in: session.account))/\(session.id).jsonl"
        guard let origin = AgentHistoryReader.origin(ofFile: transcript, id: session.id) else { return [] }
        let folder = (AgentProjectFolder.path(for: session.cwd, in: session.account) as NSString).lastPathComponent
        let fm = FileManager.default
        for account in accounts where account.provider == .claude {
            let near = account.dir + "/projects/" + folder + "/" + origin
            if fm.fileExists(atPath: near + ".jsonl") { return [near + "/subagents"] }
        }
        for account in accounts where account.provider == .claude {
            for project in (try? fm.contentsOfDirectory(atPath: account.dir + "/projects")) ?? [] {
                let path = account.dir + "/projects/" + project + "/" + origin
                if fm.fileExists(atPath: path + ".jsonl") { return [path + "/subagents"] }
            }
        }
        return []
    }

    private static func read(folder dir: String) -> [AgentSubagent] {
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".meta.json") }.compactMap { file -> AgentSubagent? in
            guard let meta = json(dir + "/" + file) else { return nil }
            let id = String(file.dropLast(".meta.json".count))
            let log = dir + "/" + id + ".jsonl"
            let date = (try? fm.attributesOfItem(atPath: log))?[.modificationDate] as? Date ?? .distantPast
            return AgentSubagent(id: id, type: meta["agentType"] as? String ?? "agent",
                                 description: meta["description"] as? String ?? id, lastWrite: date,
                                 finished: meta["finished"] as? Bool,
                                 knowsFinished: meta["finished"] != nil || meta["spawnDepth"] != nil, dir: dir)
        }
    }
}

func json(_ path: String) -> [String: Any]? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

extension AgentAccount {
    /// The provider's logo (docs/adr/0020-provider-logos.md): Claude, or
    /// OpenAI for a ChatGPT login used by Codex.
    public var logo: ProviderLogo { provider == .codex ? .openai : .claude }
}
