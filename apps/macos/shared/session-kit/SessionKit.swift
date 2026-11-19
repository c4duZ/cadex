import Foundation

/// What a feature adds to every Claude Code session Cadex opens: settings
/// (hooks, permissions), plugin folders (skills) and MCP servers. Features
/// contribute through the app (apps/macos/app), never by importing each
/// other (docs/plans/18-accounts-and-sessions.md, phase B).
public struct SessionKitPart {
    /// Merged into the kit's `--settings`: objects merge, arrays add up
    /// (two features' hooks on the same event both run).
    public var settings: [String: Any]
    public var pluginDirs: [String]
    public var mcpServers: [String: Any]
    /// Settings that depend on the session's account (its folder, ~/.claude
    /// for the default one), merged after `settings` the same way: the
    /// memory's own workspace per account when sharing is off (plan 22,
    /// phase C).
    public var perAccount: ((_ accountDir: String) -> [String: Any])?
    /// Settings that depend on the session's folder too, merged last, only
    /// when the caller knows the folder: Claude's automatic memory folder
    /// per project (plan 22, phase C).
    public var perSession: ((_ accountDir: String, _ cwd: String) -> [String: Any])?
    /// Whether the part goes into a session in `cwd`, when the caller knows
    /// the folder: false leaves its settings and plugin folders out (the
    /// memory off in a project, plan 35 I). Its MCP servers are per account
    /// (one file for every session of it) and stay.
    public var appliesTo: ((_ cwd: String) -> Bool)?

    public init(settings: [String: Any] = [:], pluginDirs: [String] = [], mcpServers: [String: Any] = [:],
                perAccount: ((_ accountDir: String) -> [String: Any])? = nil,
                perSession: ((_ accountDir: String, _ cwd: String) -> [String: Any])? = nil,
                appliesTo: ((_ cwd: String) -> Bool)? = nil) {
        self.appliesTo = appliesTo
        self.settings = settings
        self.pluginDirs = pluginDirs
        self.mcpServers = mcpServers
        self.perAccount = perAccount
        self.perSession = perSession
    }
}

/// The session kit (docs/adr/0021-cadex-managed-accounts.md): the one piece
/// that builds what a session opened by Cadex gets: `--settings`,
/// `--plugin-dir`, `--mcp-config` and the tab's environment. It is the only
/// way Cadex puts anything into a Claude Code session; nothing is written in
/// any account's own configuration. Never touches a token.
@MainActor
public final class SessionKit {
    public static let shared = SessionKit()

    /// Where the kit's files go (`~/Library/Application Support/Cadex/kit`).
    public var folder: String
    /// The `cadex` program; nil leaves the status line out (no usage, but
    /// the session works).
    public var toolsPath: String?
    /// The environment a new tab inherits: Cadex's own.
    public var environment: [String: String]
    /// agents.stateHooks: the hooks that tell the app what a session does
    /// (plan 19). Off, only the status line and the token.
    public var hooksEnabled = true
    /// CLAUDE_CODE_FORCE_SYNC_OUTPUT=1 in the settings' env (SessionKitFiles).
    public var synchronizedOutput = true
    /// Claude Code's theme for the session ("dark" or "light", plan 33 phase B): fixed 24-bit colors
    /// the terminal knows and swaps for the theme's (ClaudeDress); its -ansi themes, used since plan
    /// 28, have no diff background (measured 2026-11-18, docs/spec/terminal.md). nil: the account's own.
    public var claudeTheme: String?
    /// agentTools.enabled (plan 20): the folder of `cadex` goes first on the
    /// session's PATH, so the agent runs it (docs/adr/0024-agent-tools.md).
    public var agentToolsOnPath = false
    /// Where each session's token is kept (0600), read by the app's socket.
    public var tokens: String = SessionKit.tokensFolder

    /// `~/Library/Application Support/Cadex/sockets` (docs/adr/0022-terminal-daemon.md);
    /// CADEX_SOCKETS_DIR for a test instance, which must not take the
    /// owner's app.sock (every `make perf` did until 2026-11-15).
    public nonisolated static var socketsFolder: String {
        if let dir = ProcessInfo.processInfo.environment["CADEX_SOCKETS_DIR"], !dir.isEmpty { return dir }
        return FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Application Support/Cadex/sockets"
    }

    /// `~/Library/Application Support/Cadex/sessions`: one token per
    /// session; CADEX_SESSIONS_DIR for a test instance.
    public nonisolated static var tokensFolder: String {
        if let dir = ProcessInfo.processInfo.environment["CADEX_SESSIONS_DIR"], !dir.isEmpty { return dir }
        return FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Application Support/Cadex/sessions"
    }
    private(set) var parts: [String: SessionKitPart] = [:]

    /// The parts a session gets: all but those it goes without and those
    /// that do not apply to its folder.
    func parts(cwd: String?, leaving: Set<String>) -> [(id: String, part: SessionKitPart)] {
        parts.keys.sorted().compactMap { id in
            let part = parts[id]!
            if leaving.contains(id) { return nil }
            if let cwd, !cwd.isEmpty, let applies = part.appliesTo, !applies(cwd) { return nil }
            return (id, part)
        }
    }

    init(folder: String? = nil, toolsPath: String? = SessionKit.findTools(),
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // CADEX_KIT_DIR: a test instance's own kit files (plan 24 phase C).
        let testFolder = environment["CADEX_KIT_DIR"].flatMap { $0.isEmpty ? nil : $0 }
        self.folder = folder ?? testFolder ?? home + "/Library/Application Support/Cadex/kit"
        self.toolsPath = toolsPath
        self.environment = environment
        // A kit with a folder of its own (tests) keeps its tokens there too.
        tokens = folder.map { $0 + "/tokens" } ?? SessionKit.tokensFolder
    }

    /// A kit that writes in `folder`, with no tools and an empty environment:
    /// other features' tests check their commands with it.
    /// A kit with nothing of its own (no tools, no synchronized output):
    /// other features' tests see the plain command.
    public static func forTests(folder: String) -> SessionKit {
        let kit = SessionKit(folder: folder, toolsPath: nil, environment: [:])
        kit.synchronizedOutput = false
        return kit
    }

    public func contribute(_ id: String, _ part: SessionKitPart) { parts[id] = part }
    public func withdraw(_ id: String) { parts[id] = nil }

    /// The `cadex` program: in the app bundle (Contents/Helpers, where
    /// packaging puts it; Contents/MacOS would clash with "Cadex" on a
    /// case-insensitive disk), else the core's build output next to this
    /// source (`make run`).
    nonisolated public static func findTools(bundle: String = Bundle.main.bundlePath, source: String = #filePath) -> String? {
        let fm = FileManager.default
        let bundled = bundle + "/Contents/Helpers/cadex"
        if fm.isExecutableFile(atPath: bundled) { return bundled }
        var root = URL(fileURLWithPath: source)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let built = root.path + "/core/zig-out/bin/cadex"
        return fm.isExecutableFile(atPath: built) ? built : nil
    }

    /// The command typed in a terminal to open `claude` in an account
    /// (`configDir` nil is the default one, ~/.claude) with the kit, plus
    /// `arguments` (`--resume <id>`, the no-prompts flag). Writes the kit's
    /// files first. `defaultClaudeJSON` is the default account's
    /// .claude.json, whose MCP servers other accounts get (read only).
    /// `session`: a kit session to take again (a hibernated agent coming
    /// back, plan 19 phase F): its token stays, so the app still knows it.
    /// `cwd`: the folder the session runs in, when the caller knows it (the
    /// parts' `perSession`).
    /// `sessionEnvironment`: variables for this session only, in the
    /// `--settings` env (a dispatch's CADEX_DISPATCH_ID, plan 24); the kit's
    /// own names win over them.
    /// `leaving`: the parts this session goes without (New Session without
    /// Memory, plan 35 I).
    public func claudeCommand(configDir: String?, arguments: [String] = [], session reused: String? = nil, cwd: String? = nil,
                              defaultClaudeJSON: String = FileManager.default.homeDirectoryForCurrentUser.path + "/.claude.json",
                              sessionEnvironment: [String: String] = [:], leaving: Set<String> = []) -> String {
        let kit = launch(configDir: configDir, arguments: arguments, session: reused, cwd: cwd, defaultClaudeJSON: defaultClaudeJSON,
                         sessionEnvironment: sessionEnvironment, leaving: leaving)
        return Self.compose(unset: kit.unset, configDir: configDir, arguments: kit.arguments + arguments, pathFirst: kit.pathFirst)
    }

    /// A session opened with a prompt (plan 24, docs/adr/0033-cadex-launches-agents.md):
    /// the same command, run by `cadex claude` with `--cadex-prompt-file
    /// <file>`, which reads the file, removes it and hands the prompt to
    /// `claude` as one word of the exec: the prompt's text is never typed.
    /// The arguments kept for a relaunch after hibernating do not have the
    /// file. Nil without the `cadex` program (no way to keep the text out
    /// of the shell). Also the session's key, for the caller's records.
    public func claudeCommand(configDir: String?, arguments: [String] = [], cwd: String?, promptFile: String,
                              sessionEnvironment: [String: String] = [:],
                              defaultClaudeJSON: String = FileManager.default.homeDirectoryForCurrentUser.path + "/.claude.json") -> (command: String, session: String)? {
        guard let tools = toolsPath else { return nil }
        let kit = launch(configDir: configDir, arguments: arguments, cwd: cwd, defaultClaudeJSON: defaultClaudeJSON,
                         sessionEnvironment: sessionEnvironment)
        let command = Self.compose(unset: kit.unset, configDir: configDir, arguments: kit.arguments + arguments + ["--cadex-prompt-file", promptFile],
                                   pathFirst: kit.pathFirst, program: [tools, "claude"])
        return (command, kit.session)
    }

    /// Codex in an account (plan 29: the New Task sheet, races, the home screen): `[CODEX_HOME=dir]
    /// codex args…`; with the owner's words, `cadex codex … --cadex-prompt-file <file>`, which hands
    /// them to `codex` as one word of the exec (never typed). Codex has no kit (no hooks, no status
    /// line). Nil only with a prompt file and no `cadex`.
    public func codexCommand(home: String?, arguments: [String] = [], promptFile: String? = nil) -> String? {
        var words = home.map { ["CODEX_HOME=" + Self.quote($0)] } ?? []
        if let promptFile {
            guard let tools = toolsPath else { return nil }
            words += [Self.quote(tools), "codex"] + (arguments + ["--cadex-prompt-file", promptFile]).map(Self.quote)
        } else {
            words += ["codex"] + arguments.map(Self.quote)
        }
        return words.joined(separator: " ")
    }

    /// What the tab must not inherit: CLAUDECODE and CLAUDE_CODE_* (a
    /// session that inherited CLAUDE_CODE_CHILD_SESSION kept no transcript,
    /// 2026-11-14), and a stray CLAUDE_CONFIG_DIR for the default account.
    func unsetNames(isDefault: Bool) -> [String] {
        environment.keys.filter { name in
            name == "CLAUDECODE" || name.hasPrefix("CLAUDE_CODE_") || (isDefault && name == "CLAUDE_CONFIG_DIR")
        }.sorted()
    }

    /// `[env -u X] [CLAUDE_CONFIG_DIR=dir] claude args…`, each word quoted
    /// only when the shell needs it.
    static func compose(unset: [String], configDir: String?, arguments: [String], pathFirst: String? = nil, program: [String] = ["claude"]) -> String {
        var words: [String] = []
        if !unset.isEmpty { words += ["env"] + unset.flatMap { ["-u", $0] } }
        // The shell expands "$PATH" before claude (or env) runs: the agent's
        // Bash tool finds `cadex` first (tested 2026-11-15).
        if let pathFirst { words.append("PATH=" + quote(pathFirst) + ":\"$PATH\"") }
        if let configDir { words.append("CLAUDE_CONFIG_DIR=" + quote(configDir)) }
        words += program.map(quote)
        words += arguments.map(quote)
        return words.joined(separator: " ")
    }

    /// A word for sh, zsh and bash: as is when only safe characters, else
    /// in single quotes.
    public nonisolated static func quote(_ word: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./:=@%+,")
        if !word.isEmpty, word.unicodeScalars.allSatisfy(safe.contains) { return word }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The file name of an account, the same rule as `cadex statusline`
    /// (core/features/agent-tools/statusline.zig): every UTF-8 byte that is
    /// not an ASCII letter or digit becomes "-".
    public nonisolated static func accountKey(_ dir: String) -> String {
        let trimmed = dir.hasSuffix("/") && dir.count > 1 ? String(dir.dropLast()) : dir
        return String(decoding: trimmed.utf8.map { byte in
            (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) ? byte : 45
        }, as: UTF8.self)
    }
}
