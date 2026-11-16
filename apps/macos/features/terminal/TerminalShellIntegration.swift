import Foundation

/// The zsh integration (docs/spec/terminal.md, plan 22 phase C): a folder
/// with Cadex's own `.zshenv`, which the core puts in ZDOTDIR of every zsh
/// tab (core/features/terminal/shell_env.zig). It gives the owner's ZDOTDIR
/// back and defines a `claude` function that runs `cadex claude`, so the
/// `claude` typed in a tab gets the session kit. bash and fish get nothing.
public enum TerminalShellIntegration {
    /// The folder of the zsh files: the bundle's Resources (packaging copies
    /// it), else beside this source (`make run`).
    public static func zshFolder(resources: URL? = Bundle.main.resourceURL) -> String? {
        let fm = FileManager.default
        if let bundled = resources?.appendingPathComponent("shell-integration/zsh").path,
           fm.fileExists(atPath: bundled + "/.zshenv") { return bundled }
        // #filePath here, not as a default argument (that would be the caller's file).
        let beside = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("shell-integration/zsh").path
        return fm.fileExists(atPath: beside + "/.zshenv") ? beside : nil
    }

    /// What the app puts in its own environment before any terminal or the
    /// terminal daemon starts, so both direct tabs and the daemon's shells
    /// inherit it: CADEX_ZSH_INTEGRATION (read by the core) and CADEX_TOOLS
    /// (the `cadex` program, read by the shell function). Nothing when the
    /// folder is missing; no `cadex`, the function runs the real `claude`.
    public static func environment(zshFolder: String?, tools: String?) -> [String: String] {
        guard let zshFolder else { return [:] }
        var env = ["CADEX_ZSH_INTEGRATION": zshFolder]
        if let tools { env["CADEX_TOOLS"] = tools }
        return env
    }

    /// Sets `environment` in this process (main.swift, at launch).
    public static func export(tools: String?) {
        for (name, value) in environment(zshFolder: zshFolder(), tools: tools) { setenv(name, value, 1) }
    }
}
