import Foundation
import StateGlyph

/// What the work's tree shows (docs/spec/sidebar.md; the Sidebar mockup; plan 27 phase B): the
/// projects, each with its terminals and its tasks, and in a task its own terminals. The app
/// gathers it (this feature knows no terminal, worktree or project); the tree only draws it and
/// says what was picked.
public struct WorkTreeTerminal: Equatable, Sendable {
    /// The terminal's identity in the app, to show its tab.
    public var id: String
    public var title: String
    /// What runs in it, when an agent reports; nil: a plain shell.
    public var state: GlyphState?
    /// A short note on the right ("Opus", ":5173", "38s").
    public var note: String

    public init(id: String, title: String, state: GlyphState? = nil, note: String = "") {
        self.id = id
        self.title = title
        self.state = state
        self.note = note
    }
}

public struct WorkTreeTask: Equatable, Sendable {
    /// The task's worktree folder.
    public var id: String
    public var name: String
    public var state: GlyphState
    /// Something new since the owner last looked: the name in bold (the anatomy).
    public var unread: Bool
    /// "Claude · bkdg": who works on it.
    public var agent: String
    public var terminals: [WorkTreeTerminal]

    public init(id: String, name: String, state: GlyphState, unread: Bool = false, agent: String = "", terminals: [WorkTreeTerminal] = []) {
        self.id = id
        self.name = name
        self.state = state
        self.unread = unread
        self.agent = agent
        self.terminals = terminals
    }
}

public struct WorkTreeProject: Equatable, Sendable {
    /// The project's folder.
    public var id: String
    public var name: String
    /// "main", or empty outside git.
    public var branch: String
    public var tasks: [WorkTreeTask]
    /// The terminals in the project's own folder (not in a task's).
    public var terminals: [WorkTreeTerminal]

    public init(id: String, name: String, branch: String = "", tasks: [WorkTreeTask] = [], terminals: [WorkTreeTerminal] = []) {
        self.id = id
        self.name = name
        self.branch = branch
        self.tasks = tasks
        self.terminals = terminals
    }
}

/// What a click in the tree picked.
public enum WorkTreePick: Equatable, Sendable {
    case project(String)
    case task(String)
    case terminal(String)
}
