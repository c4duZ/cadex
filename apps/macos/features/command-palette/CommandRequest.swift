import Foundation

/// A command run with arguments by someone other than the owner: the agent
/// of a session Cadex opened (docs/adr/0024-agent-tools.md). Where it came
/// from rides along as plain values, so the command finds its terminal and
/// task through the app without this feature knowing them.
public struct CommandRequest: Sendable, Equatable {
    public let arguments: [String: String]
    /// The folder of the asking agent's terminal.
    public let folder: String
    /// The asking terminal's key in the app (its notifications go there).
    public let terminal: String
    /// The conversation's name, for what the owner sees.
    public let session: String
    /// The asking session's kit key, from its token (plan 24 D2: a run's
    /// commands find the dispatch by it, never by what the agent says).
    public var kitSession = ""
    /// The CADEX_DISPATCH_ID the agent's `cadex` sent, if any.
    public var dispatch: String?

    public init(arguments: [String: String], folder: String, terminal: String = "", session: String = "",
                kitSession: String = "", dispatch: String? = nil) {
        self.arguments = arguments
        self.folder = folder
        self.terminal = terminal
        self.session = session
        self.kitSession = kitSession
        self.dispatch = dispatch
    }

    public subscript(_ key: String) -> String? { arguments[key] }
}

/// What a command run with arguments answers: done, with a short text for
/// the agent, or refused with the reason.
public enum CommandReply: Sendable, Equatable {
    case ok(String)
    case failed(String)
}

extension Command {
    /// The same command, taking arguments when the agent runs it: no list,
    /// no question on screen; `help` says what it takes ("path=<file>
    /// [line=<n>]"). Run by the owner, it still does what `action` says.
    public func accepting(_ help: String, _ handler: @escaping @MainActor (CommandRequest) -> CommandReply) -> Command {
        var copy = self
        copy.argumentHelp = help
        copy.withArguments = handler
        return copy
    }

    /// The same, for a command that answers later (waits on a page).
    public func acceptingLater(_ help: String, _ handler: @escaping @MainActor (CommandRequest, @escaping @MainActor (CommandReply) -> Void) -> Void) -> Command {
        var copy = self
        copy.argumentHelp = help
        copy.withArgumentsLater = handler
        return copy
    }
}
