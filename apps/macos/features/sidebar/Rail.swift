import Foundation
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

    public init(id: String, name: String, tint: [Double]? = nil, state: GlyphState? = nil, open: Bool = false) {
        self.id = id
        self.name = name
        self.tint = tint
        self.state = state
        self.open = open
    }

    /// What the tile shows until the project has an image (plan 36 phase D): the name's first
    /// letter or digit, upper case.
    public var mark: String {
        name.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "•"
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
