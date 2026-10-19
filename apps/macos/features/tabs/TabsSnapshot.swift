import CoreGraphics
import Foundation

/// What a window's tabs are, in a form that can be saved and rebuilt
/// (docs/spec/spaces.md): the order, each terminal tab's panes with their
/// folders and proportions, the documents by identity, and the active tab.
/// Not the terminals' content: each pane starts a new shell.
public struct TabsSnapshot: Codable, Equatable, Sendable {
    public indirect enum Layout: Codable, Equatable, Sendable {
        case pane(folder: String)
        /// `sideBySide`: ⌘D's split; otherwise one above the other.
        case split(sideBySide: Bool, ratio: Double, first: Layout, second: Layout)

        /// The panes' folders in reading order.
        public var folders: [String] {
            switch self {
            case .pane(let folder): [folder]
            case .split(_, _, let a, let b): a.folders + b.folders
            }
        }
    }

    public enum Item: Codable, Equatable, Sendable {
        /// `focus`: the focused pane's position in reading order.
        case terminal(title: String?, layout: Layout, focus: Int)
        /// A document tab, reopened by the app from its identity (a path,
        /// "history:<repo>"); the ones it does not know stay closed.
        case document(identity: String)
    }

    public var items: [Item]
    /// Index in `items` of the active tab.
    public var active: Int?

    public init(items: [Item] = [], active: Int? = nil) {
        self.items = items
        self.active = active
    }
}

extension PaneTree {
    /// The layout of this tree, each pane by its folder.
    func snapshot(folder: (Int) -> String) -> TabsSnapshot.Layout {
        switch self {
        case .leaf(let id):
            return .pane(folder: folder(id))
        case .split(let axis, let a, let b, let ratio):
            return .split(sideBySide: axis == .horizontal, ratio: Double(ratio),
                          first: a.snapshot(folder: folder), second: b.snapshot(folder: folder))
        }
    }

    /// The tree of a saved layout, numbering its panes with `nextPane`
    /// (each call gives a new id), in reading order.
    static func from(_ layout: TabsSnapshot.Layout, nextPane: () -> Int) -> PaneTree {
        switch layout {
        case .pane:
            return .leaf(nextPane())
        case .split(let sideBySide, let ratio, let first, let second):
            let a = from(first, nextPane: nextPane)
            let b = from(second, nextPane: nextPane)
            // A hand-edited file could hold any number; a pane needs room.
            let r = CGFloat(min(max(ratio, 0.1), 0.9))
            return .split(sideBySide ? .horizontal : .vertical, a, b, ratio: r)
        }
    }
}
