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
