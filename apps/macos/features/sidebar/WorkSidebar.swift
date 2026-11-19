import Foundation
import StateGlyph

/// The sidebar's model (docs/adr/0039-sidebar-with-work-and-files.md; plan 38): the app gathers it,
/// the sidebar only draws it and says what was picked.
public struct WorkProject: Equatable, Sendable {
    /// The project's folder.
    public var id: String
    public var name: String
    /// The project's color (red, green, blue from 0 to 1) under its initials; nil: the avatar's own.
    public var tint: [Double]?
    /// The project's picture (a file) or emoji in place of the initials.
    public var image: String?
    public var emoji: String?
    /// The most urgent state of its terminals; nil or idle: none.
    public var state: GlyphState?
    /// Its terminals open; 0 is "nothing open".
    public var terminals: Int
    /// Its agents waiting on the owner (permission, question): the amber count when it is folded.
    public var waiting: Int
    /// Unfolded, its main and tasks show under it.
    public var expanded: Bool
    public var places: [WorkPlace]
    public var pinned: Bool

    public init(id: String, name: String, tint: [Double]? = nil, image: String? = nil, emoji: String? = nil,
                state: GlyphState? = nil, terminals: Int = 0, waiting: Int = 0, expanded: Bool = false,
                places: [WorkPlace] = [], pinned: Bool = true) {
        self.id = id
        self.name = name
        self.tint = tint
        self.image = image
        self.emoji = emoji
        self.state = state
        self.terminals = terminals
        self.waiting = waiting
        self.expanded = expanded
        self.places = places
        self.pinned = pinned
    }

    /// Two letters for the avatar: the first two words' initials ("bhband-site": BS), else the
    /// name's first two letters ("cadex": CA), upper case; "•" with none.
    public var initials: String {
        let words = name.split { !$0.isLetter && !$0.isNumber }
        if words.count >= 2, let a = words[0].first, let b = words[1].first { return (String(a) + String(b)).uppercased() }
        let letters = name.filter { $0.isLetter || $0.isNumber }
        return letters.isEmpty ? "•" : String(letters.prefix(2)).uppercased()
    }

    /// The state worth a mark (idle has none).
    public var badge: GlyphState? { state == .idle ? nil : state }
}

/// A place of a project: its main folder or one of its tasks (worktrees). Picked, its terminals go
/// to the top bar.
public struct WorkPlace: Equatable, Sendable {
    /// The folder (the project's for main, the worktree's for a task).
    public var id: String
    public var name: String
    public var isMain: Bool
    public var state: GlyphState?
    public var terminals: Int

    public init(id: String, name: String, isMain: Bool = false, state: GlyphState? = nil, terminals: Int = 0) {
        self.id = id
        self.name = name
        self.isMain = isMain
        self.state = state
        self.terminals = terminals
    }
}

/// The sidebar's two views (ADR 0039): Work first, Files second.
public enum WorkSidebarMode: String, Sendable {
    case work
    case files
}
