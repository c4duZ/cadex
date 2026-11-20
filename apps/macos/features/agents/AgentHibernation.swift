import CommandPalette
import Foundation
import SessionKit
import Strings

/// Hibernation (docs/spec/agents.md, plan 19 phase F): an agent that is done
/// or idle, not looked at, for agents.hibernateAfterMinutes ends (SIGTERM:
/// Claude Code exits in under a second and keeps the conversation, tested
/// 2026-11-15), and comes back with `claude --resume <id>` in the same
/// folder and account, by the kit with the same token, when its terminal
/// is opened again. The rules here; the terminals are the app's.
public enum AgentHibernation {
    /// Time to hibernate: quiet for `minutes` (0 is off) and not looked at.
    public static func isDue(quietSince: Date?, lookedAt: Bool, minutes: Int, now: Date = Date()) -> Bool {
        guard minutes > 0, !lookedAt, let quietSince else { return false }
        return now.timeIntervalSince(quietSince) >= Double(minutes) * 60
    }

    /// When to look again: the moment it becomes due, nil when it never will.
    public static func dueAt(quietSince: Date?, minutes: Int) -> Date? {
        guard minutes > 0, let quietSince else { return nil }
        return quietSince.addingTimeInterval(Double(minutes) * 60)
    }

    /// The account's folder from a conversation's file
    /// (`<account>/projects/<project>/<id>.jsonl`); nil for the default
    /// account (~/.claude), which the kit opens without CLAUDE_CONFIG_DIR.
    public static func configDir(transcript: String, home: String = NSHomeDirectory()) -> String? {
        guard let range = transcript.range(of: "/projects/", options: .backwards) else { return nil }
        let dir = String(transcript[..<range.lowerBound])
        return dir == home + "/.claude" ? nil : dir
    }

    /// What is typed in the terminal to bring the conversation back: into
    /// its folder, then `claude --resume <id>` by the kit, in its account,
    /// with the arguments the session was opened with, keeping the kit
    /// session (and so the token) when it is still there. Without kept
    /// arguments, the permission flag as agents.launchSkipPermissions says.
    @MainActor
    public static func resumeCommand(sessionID: String, folder: String, configDir: String?, kitSession: String?,
                                     skipPermissions: Bool, kit: SessionKit = .shared) -> String {
        let flags = openedFlags(kitSession: kitSession, skipPermissions: skipPermissions, kit: kit)
        let claude = kit.claudeCommand(configDir: configDir, arguments: ["--resume", sessionID] + flags, session: kitSession, cwd: folder)
        return "cd " + SessionKit.quote(folder) + " && " + claude
    }

    /// Switching account with the same conversation: its file resumed by path with --fork-session
    /// in the other account (what History's Continue in Another Account does: by the id alone the
    /// other account finds nothing, and without the fork it writes into the first one's file,
    /// tested 2026-11-14), with the flags the session was opened with and a kit session of its own.
    @MainActor
    public static func carryCommand(transcript: String, folder: String, configDir: String?, kitSession: String?,
                                    skipPermissions: Bool, kit: SessionKit = .shared) -> String {
        let flags = openedFlags(kitSession: kitSession, skipPermissions: skipPermissions, kit: kit)
        let claude = kit.claudeCommand(configDir: configDir, arguments: ["--resume", transcript, "--fork-session"] + flags, cwd: folder)
        return "cd " + SessionKit.quote(folder) + " && " + claude
    }

    /// The arguments the session was opened with, without its conversation; with none kept, the
    /// permission flag as agents.launchSkipPermissions says.
    @MainActor
    static func openedFlags(kitSession: String?, skipPermissions: Bool, kit: SessionKit) -> [String] {
        kitSession.flatMap(kit.arguments(of:)).map(withoutConversation) ?? (skipPermissions ? ["--dangerously-skip-permissions"] : [])
    }

    /// The arguments without what picked the conversation then (`--resume
    /// <id>`, `--continue`, `--fork-session`): the resume picks it now.
    static func withoutConversation(_ arguments: [String]) -> [String] {
        var out: [String] = []
        var skipNext = false
        for argument in arguments {
            if skipNext { skipNext = false; continue }
            switch argument {
            case "--resume", "-r": skipNext = true
            case "--continue", "-c", "--fork-session": continue
            default: out.append(argument)
            }
        }
        return out
    }

    /// agents.hibernate (the focused terminal's agent, now) and
    /// agents.restart (bring back the one that quit or hibernated).
    @MainActor
    public static func commands(hibernate: @escaping @MainActor () -> Void, restart: @escaping @MainActor () -> Void) -> [Command] {
        [
            Command(id: "agents.hibernate", title: T("Hibernate This Agent", "Hibernar este agente"),
                    keywords: ["hibernate", "sleep", "stop", "memory", "hibernar", "dormir", "memória"], category: .terminal,
                    action: .run { hibernate() }),
            Command(id: "agents.restart", title: T("Restart This Agent", "Reiniciar este agente"),
                    keywords: ["restart", "resume", "relaunch", "reiniciar", "retomar"], category: .terminal,
                    action: .run { restart() }),
        ]
    }
}
