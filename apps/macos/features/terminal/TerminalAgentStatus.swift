import Foundation

/// What an agent in a terminal says it is doing, by the program status
/// protocol (OSC 7501) that Claude Code speaks to terminals that answer its
/// query (test of 2026-11-14; docs/adr/0022-terminal-daemon.md). The core
/// keeps the last report; this is its copy for the app.
public struct TerminalAgentStatus: Equatable, Sendable {
    public enum State: UInt8, Sendable {
        case none = 0, idle, working, done, blocked, failed
    }

    /// What a blocked agent needs from you.
    public enum Kind: UInt8, Sendable {
        case none = 0, permission, question, auth
    }

    public let state: State
    public let kind: Kind
    /// "claude-code".
    public let app: String
    /// "approve Bash: touch x", "Creating empty file…"; may be empty.
    public let message: String

    public init(state: State, kind: Kind, app: String, message: String) {
        self.state = state
        self.kind = kind
        self.app = app
        self.message = message
    }

    /// Waiting on you: a permission, a question or a login.
    public var needsYou: Bool { state == .blocked }
}
