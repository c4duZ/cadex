import CommandPalette
import Foundation
import Strings

/// What the app does for the agent-tools commands (it holds the windows,
/// the opener and the notifications).
public struct AgentToolsActions {
    public var openFile: @MainActor (CommandRequest) -> CommandReply
    public var openDiff: @MainActor (CommandRequest) -> CommandReply
    public var notify: @MainActor (CommandRequest) -> CommandReply
    /// Run by the owner, the agent's commands do the owner's nearest one
    /// (search for a file, the Git page, the feed): runs that command's id.
    public var runOwnerCommand: @MainActor (String) -> Void
    public var toggle: @MainActor () -> Void
    public var showSessions: @MainActor () -> Void

    public init(openFile: @escaping @MainActor (CommandRequest) -> CommandReply, openDiff: @escaping @MainActor (CommandRequest) -> CommandReply,
                notify: @escaping @MainActor (CommandRequest) -> CommandReply, runOwnerCommand: @escaping @MainActor (String) -> Void,
                toggle: @escaping @MainActor () -> Void, showSessions: @escaping @MainActor () -> Void) {
        self.openFile = openFile
        self.openDiff = openDiff
        self.notify = notify
        self.runOwnerCommand = runOwnerCommand
        self.toggle = toggle
        self.showSessions = showSessions
    }
}

/// The agent-tools commands (docs/spec/agent-tools.md, plan 20 phase B):
/// the agent's open-file, open-diff and notify, which take arguments, and
/// the owner's toggle and list of the sessions using the Cadex.
public enum AgentToolsCommands {
    @MainActor
    public static func commands(_ actions: AgentToolsActions) -> [Command] {
        [
            Command(id: "agent-tools.open-file", title: T("Open a File for the Agent", "Abrir um arquivo para o agente"),
                    keywords: ["agent", "open", "file", "agente", "abrir", "arquivo"], category: .terminal,
                    action: .run { actions.runOwnerCommand("search.files") })
                .accepting("path=<file> [line=<n>]", actions.openFile),
            Command(id: "agent-tools.open-diff", title: T("Open a Diff for the Agent", "Abrir um diff para o agente"),
                    keywords: ["agent", "diff", "changes", "agente", "mudanças"], category: .terminal,
                    action: .run { actions.runOwnerCommand("git.show") })
                .accepting("[path=<file>]", actions.openDiff),
            Command(id: "agent-tools.notify", title: T("Agents' Notes", "Avisos dos agentes"),
                    keywords: ["agent", "notify", "notification", "agente", "aviso", "notificação"], category: .terminal,
                    action: .run { actions.runOwnerCommand("agents.show-feed") })
                .accepting("text=<one sentence>", actions.notify),
            Command(id: "agent-tools.toggle", title: T("Turn Agent Tools On or Off", "Ligar ou desligar as ferramentas do agente"),
                    keywords: ["agent", "tools", "cli", "mcp", "agente", "ferramentas"], category: .terminal,
                    action: .run { actions.toggle() }),
            Command(id: "agent-tools.show-sessions", title: T("Show Sessions Using Cadex…", "Mostrar as sessões usando o Cadex…"),
                    keywords: ["agent", "tools", "sessions", "agente", "ferramentas", "sessões"], category: .terminal,
                    action: .run { actions.showSessions() }),
        ]
    }
}
