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

    public init(settings: [String: Any] = [:], pluginDirs: [String] = [], mcpServers: [String: Any] = [:]) {
        self.settings = settings
        self.pluginDirs = pluginDirs
        self.mcpServers = mcpServers
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
    private(set) var parts: [String: SessionKitPart] = [:]

    init(folder: String? = nil, toolsPath: String? = SessionKit.findTools(),
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.folder = folder ?? home + "/Library/Application Support/Cadex/kit"
        self.toolsPath = toolsPath
        self.environment = environment
    }

    /// A kit that writes in `folder`, with no tools and an empty environment:
    /// other features' tests check their commands with it.
    public static func forTests(folder: String) -> SessionKit {
        SessionKit(folder: folder, toolsPath: nil, environment: [:])
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
    public func claudeCommand(configDir: String?, arguments: [String] = [],
                              defaultClaudeJSON: String = FileManager.default.homeDirectoryForCurrentUser.path + "/.claude.json") -> String {
        let accountDir = configDir ?? FileManager.default.homeDirectoryForCurrentUser.path + "/.claude"
        let key = Self.accountKey(accountDir)
        var args: [String] = []
        if let settings = writeSettings(key: key, accountDir: accountDir) { args += ["--settings", settings] }
        for dir in parts.values.flatMap(\.pluginDirs).sorted() { args += ["--plugin-dir", dir] }
        if let mcp = writeMCP(key: key, isDefault: configDir == nil, defaultClaudeJSON: defaultClaudeJSON) { args += ["--mcp-config", mcp] }
        return Self.compose(unset: unsetNames(isDefault: configDir == nil), configDir: configDir, arguments: args + arguments)
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
    static func compose(unset: [String], configDir: String?, arguments: [String]) -> String {
        var words: [String] = []
        if !unset.isEmpty { words += ["env"] + unset.flatMap { ["-u", $0] } }
        if let configDir { words.append("CLAUDE_CONFIG_DIR=" + quote(configDir)) }
        words.append("claude")
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
