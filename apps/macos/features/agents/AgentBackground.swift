import Foundation

/// Sessions running in the background (agent view, `claude --bg`). They
/// have no registry in sessions/ when parked, so the Agents page missed the
/// "blocked" ones waiting for the owner, some for days (test loop,
/// 2026-11-14). The source is `claude agents --json`, the interface the
/// docs support (their jobs/ files are internal); 0.15 s of CPU a call, so
/// it runs only when an account's jobs/ folder changes, never on a timer.
public enum AgentBackground {
    /// The background sessions still open in `data` (the command's output):
    /// working or blocked. Done, failed and stopped ones are left out, as
    /// are interactive ones, which sessions/ already lists.
    public static func parse(_ data: Data, account: AgentAccount) -> [AgentSession] {
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard entry["kind"] as? String == "background", let job = entry["id"] as? String,
                  let id = entry["sessionId"] as? String, let cwd = entry["cwd"] as? String else { return nil }
            let status: AgentSession.Status
            switch entry["state"] as? String ?? "" {
            case "working": status = .working
            case "blocked": status = .waiting
            default: return nil
            }
            let millis = (entry["startedAt"] as? NSNumber)?.doubleValue ?? 0
            var session = AgentSession(account: account, pid: (entry["pid"] as? NSNumber)?.int32Value ?? 0, id: id,
                                       name: entry["name"] as? String ?? (cwd as NSString).lastPathComponent,
                                       cwd: cwd, status: status, since: Date(timeIntervalSince1970: millis / 1000))
            session.job = job
            session.waitingFor = entry["waitingFor"] as? String
            return session
        }
    }

    /// The open sessions of another machine, from its `claude agents
    /// --json` read over ssh (plan 23, "Run on"; ADR 0031): interactive and
    /// background, as there is no sessions/ folder to read there. Each
    /// carries the machine; its account is a stand-in named after it.
    /// Ended ones are left out. The interactive entries' shape was not seen
    /// on a real session yet (only `[]`, 2026-11-16): read defensively.
    public static func parseRemote(_ data: Data, machine: String, destination: String) -> [AgentSession] {
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        let account = AgentAccount(dir: "ssh://" + destination, name: machine, isDefault: false)
        return list.compactMap { entry in
            guard let id = entry["sessionId"] as? String ?? entry["id"] as? String, let cwd = entry["cwd"] as? String else { return nil }
            let state = (entry["state"] as? String ?? entry["status"] as? String ?? "").lowercased()
            let status: AgentSession.Status
            switch state {
            case "working", "busy", "running": status = .working
            case "blocked", "waiting", "idle": status = .waiting
            case "done", "completed", "failed", "stopped", "ended": return nil
            default: status = .other(state)
            }
            let millis = (entry["startedAt"] as? NSNumber)?.doubleValue ?? 0
            var session = AgentSession(account: account, pid: 0, id: id, name: entry["name"] as? String ?? (cwd as NSString).lastPathComponent,
                                       cwd: cwd, status: status, since: Date(timeIntervalSince1970: millis / 1000))
            session.machine = machine
            session.job = entry["kind"] as? String == "background" ? entry["id"] as? String : nil
            session.waitingFor = entry["waitingFor"] as? String
            return session
        }
    }

    /// The account's background jobs that run now: those its daemon's
    /// roster (`daemon/roster.json`, Claude Code's own, read defensively)
    /// lists among `workers` with a live process. `claude agents` also lists
    /// parked jobs as "blocked", some for months, in folders long gone; they
    /// have no worker, even with the daemon up (2026-11-14, Claude Code
    /// 2.1.325: a fresh `claude --bg` was in workers, the parked ones not).
    public static func liveJobs(_ account: AgentAccount, alive: (Int32) -> Bool = { kill($0, 0) == 0 }) -> Set<String> {
        guard let roster = json(account.dir + "/daemon/roster.json"),
              let workers = roster["workers"] as? [String: Any] else { return [] }
        return Set(workers.compactMap { job, value in
            guard let pid = ((value as? [String: Any])?["pid"] as? NSNumber)?.int32Value, pid > 0, alive(pid) else { return nil }
            return job
        })
    }

    /// One session per job: `claude agents` lists the same job under several
    /// accounts (the owner's ~/.claude, ~/.claude-bhband and ~/.claude-diogo
    /// all had "Subir docker"); the one whose folder holds its conversation
    /// keeps it, else the first.
    public static func distinct(_ sessions: [AgentSession]) -> [AgentSession] {
        var out: [AgentSession] = []
        for session in sessions {
            if let index = out.firstIndex(where: { $0.job == session.job }) {
                if !owns(out[index]), owns(session) { out[index] = session }
            } else {
                out.append(session)
            }
        }
        return out
    }

    static func owns(_ session: AgentSession) -> Bool {
        FileManager.default.fileExists(atPath: "\(AgentProjectFolder.path(for: session.cwd, in: session.account))/\(session.id).jsonl")
    }

    /// The `claude` binary: the places its installers put it.
    public static func claudePath(home: String = NSHomeDirectory()) -> String? {
        [home + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs `claude agents --json` for `account`, at most 5 s. The
    /// environment loses CLAUDECODE and CLAUDE_CODE_* (a Cadex started from
    /// a Claude Code session would pass them on, and CLAUDE_CODE_CHILD_SESSION
    /// changes how the CLI behaves; test loop, 2026-11-14).
    public static func read(_ account: AgentAccount, claude: String) -> [AgentSession] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claude)
        process.arguments = ["agents", "--json"]
        var env = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("CLAUDE_CODE_") && $0.key != "CLAUDECODE" }
        if account.isDefault { env["CLAUDE_CONFIG_DIR"] = nil } else { env["CLAUDE_CONFIG_DIR"] = account.dir }
        process.environment = env
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let deadline = DispatchTime.now() + 5
        DispatchQueue.global().asyncAfter(deadline: deadline) { if process.isRunning { process.terminate() } }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? parse(data, account: account) : []
    }
}
