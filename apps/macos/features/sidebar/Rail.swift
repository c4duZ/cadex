import Foundation
import Icons
import StateGlyph

/// One project in the rail (docs/adr/0038-rail-and-side-column.md; the Rail mockup): the app
/// gathers it, the rail only draws it and says which was picked.
public struct RailProject: Equatable, Sendable {
    /// The project's folder.
    public var id: String
    /// The name the owner gave, or the folder's (shown under the pointer).
    public var name: String
    /// The project's color (project.set-color) as red, green and blue from 0 to 1; nil: the tile's
    /// own background.
    public var tint: [Double]?
    /// The most urgent state of its terminals; nil or idle: no badge.
    public var state: GlyphState?
    /// It has a terminal open: the dot under the tile, as the Dock's.
    public var open: Bool
    /// The project's picture (a file), shown over the whole tile; nil: the emoji or the letter.
    public var image: String?
    /// An emoji in place of the letter (plan 36 phase B).
    public var emoji: String?
    /// Kept in the rail with no terminal; the open ones that are not come after a line, as the Dock's.
    public var pinned: Bool

    public init(id: String, name: String, tint: [Double]? = nil, state: GlyphState? = nil, open: Bool = false,
                image: String? = nil, emoji: String? = nil, pinned: Bool = true) {
        self.pinned = pinned
        self.id = id
        self.name = name
        self.tint = tint
        self.state = state
        self.open = open
        self.image = image
        self.emoji = emoji
    }

    /// What the tile shows without a picture: the emoji, else the name's first letter or digit,
    /// upper case (plan 36 phase B).
    public var mark: String {
        if let emoji, !emoji.isEmpty { return emoji }
        return name.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "•"
    }

    /// The badge's state: only what someone should see (idle has none).
    public var badge: GlyphState? {
        guard let state, state != .idle else { return nil }
        return state
    }
}

/// The rail's foot: the pages that are about every project (ADR 0038).
public enum RailFoot: String, Sendable {
    case projects
    case automations
}

/// A page of the side column, as the rail shows it (docs/adr/0038-rail-and-side-column.md, revised
/// 2026-11-18): its icon, its name under the pointer, the command that opens the column on it.
public struct RailPage: Equatable, Sendable {
    public var id: String
    public var title: String
    public var icon: Icon
    public var command: String

    public init(id: String, title: String, icon: Icon, command: String) {
        self.id = id
        self.title = title
        self.icon = icon
        self.command = command
    }
}
