import Foundation
import Security

/// The memory agent's side in the app (plan 22 phase G,
/// docs/adr/0029-memory-agent.md): the engine runs the jobs with the
/// owner's `claude -p`; the app only writes what the owner set
/// (`<memory>/agent.json`, read by the engine at each job) and asks through
/// `cadex memory-agent` (the core's client; the app never talks to
/// memory.sock itself).
public enum MemoryAgent {
    /// What the owner set, as the engine reads it.
    public struct Config: Equatable, Sendable {
        public var enabled: Bool
        public var dailyBudgetUsd: Double
        public var requireApproval: Bool
        /// The default account's folder; nil for ~/.claude.
        public var configDir: String?
        /// A project's own account, by repository root.
        public var projectAccounts: [String: String]
        public var claude: String?

        public init(enabled: Bool, dailyBudgetUsd: Double, requireApproval: Bool, configDir: String?,
                    projectAccounts: [String: String], claude: String?) {
            self.enabled = enabled
            self.dailyBudgetUsd = dailyBudgetUsd
            self.requireApproval = requireApproval
            self.configDir = configDir
            self.projectAccounts = projectAccounts
            self.claude = claude
        }

        /// The JSON the engine reads (core/features/memory/server, agent.json).
        public var json: [String: Any] {
            ["enabled": enabled, "daily_budget_usd": dailyBudgetUsd, "require_approval": requireApproval,
             "model": "haiku", "call_budget_usd": 0.25,
             "claude": claude.map { $0 as Any } ?? NSNull(), "config_dir": configDir.map { $0 as Any } ?? NSNull(),
             "project_accounts": projectAccounts]
        }
    }

    /// An account setting ("~/.claude-work", "" for the default) as a folder.
    public nonisolated static func accountFolder(_ setting: String, home: String = NSHomeDirectory()) -> String? {
        let trimmed = setting.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        let path = trimmed.hasPrefix("~/") ? home + trimmed.dropFirst(1) : trimmed
        return path == home + "/.claude" ? nil : path
    }

    /// The `claude` the engine runs (the paths Agents looks in), or nil.
    public nonisolated static func findClaude(home: String = NSHomeDirectory()) -> String? {
        [home + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Writes `<folder>/agent.json` (0600) when it changed.
    @discardableResult
    public nonisolated static func write(_ config: Config, folder: String) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: config.json, options: [.prettyPrinted, .sortedKeys]) else { return false }
        let path = folder + "/agent.json"
        if FileManager.default.contents(atPath: path) == data { return true }
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return FileManager.default.createFile(atPath: path, contents: data, attributes: [.posixPermissions: 0o600])
    }

    /// The app's own token for `cadex memory-agent`, in the tokens folder
    /// the engine reads (`memory-agent.token`, 64 hex, 0600), made once.
    public nonisolated static func appToken(tokens: String) -> String? {
        let path = tokens + "/memory-agent.token"
        if let existing = try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           existing.count == 64 { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try? FileManager.default.createDirectory(atPath: tokens, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return FileManager.default.createFile(atPath: path, contents: Data(token.utf8), attributes: [.posixPermissions: 0o600]) ? token : nil
    }

    /// The environment `cadex memory-agent` needs: the app's token and the
    /// same memory variables the kit gives the hooks.
    public nonisolated static func environment(engine: String?, token: String,
                                               base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base.filter { !$0.key.hasPrefix("CLAUDE_CODE_") && $0.key != "CLAUDECODE" }
        env.merge(MemoryKit.env(engine: engine, environment: base)) { _, new in new }
        env["CADEX_SESSION_TOKEN"] = token
        env["CADEX_SESSIONS_DIR"] = base["CADEX_SESSIONS_DIR"]
        return env
    }

    /// Runs `cadex memory-agent <words>` off the main thread; `done` gets
    /// the exit code and the JSON it printed, on the main thread.
    public nonisolated static func run(tools: String, words: [String], environment: [String: String],
                                       done: @escaping @MainActor @Sendable (Int32, [String: Any]) -> Void) {
        runRaw(tools: tools, words: words, environment: environment, input: nil) { code, data in
            done(code, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
        }
    }

    /// The same for a plain-text answer (`briefing`): the text as printed.
    public nonisolated static func runText(tools: String, words: [String], environment: [String: String],
                                           done: @escaping @MainActor @Sendable (Int32, String) -> Void) {
        runRaw(tools: tools, words: words, environment: environment, input: nil) { code, data in
            done(code, String(decoding: data, as: UTF8.self))
        }
    }

    /// The same with `input` on stdin (`write-page`'s body), JSON back.
    public nonisolated static func run(tools: String, words: [String], input: String, environment: [String: String],
                                       done: @escaping @MainActor @Sendable (Int32, [String: Any]) -> Void) {
        runRaw(tools: tools, words: words, environment: environment, input: Data(input.utf8)) { code, data in
            done(code, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
        }
    }

    /// The process itself: stdout read whole, the code and the bytes on the
    /// main thread. stderr apart, so a warning never breaks the JSON or the
    /// briefing; it stands in only for an empty stdout (an error said there).
    nonisolated static func runRaw(tools: String, words: [String], environment: [String: String], input: Data?,
                                   done: @escaping @MainActor @Sendable (Int32, Data) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tools)
            process.arguments = ["memory-agent"] + words
            process.environment = environment
            let out = Pipe()
            process.standardOutput = out
            let err = Pipe()
            process.standardError = err
            let stdin = Pipe()
            process.standardInput = input == nil ? FileHandle.nullDevice : stdin
            var code: Int32 = 1
            var data = Data()
            if (try? process.run()) != nil {
                if let input {
                    // Written from another queue: a body bigger than the pipe's
                    // buffer would block while we wait on stdout.
                    DispatchQueue.global(qos: .userInitiated).async {
                        stdin.fileHandleForWriting.write(input)
                        try? stdin.fileHandleForWriting.close()
                    }
                }
                // Both pipes drained at once: a full stderr would block the child.
                let errors = ErrorBox()
                let group = DispatchGroup()
                DispatchQueue.global(qos: .userInitiated).async(group: group) { errors.data = err.fileHandleForReading.readDataToEndOfFile() }
                data = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                code = process.terminationStatus
                if data.isEmpty { data = errors.data }
            }
            let result = data
            DispatchQueue.main.async { MainActor.assumeIsolated { done(code, result) } }
        }
    }
}

/// stderr's bytes, handed from the reading queue (read after group.wait()).
private final class ErrorBox: @unchecked Sendable {
    var data = Data()
}
