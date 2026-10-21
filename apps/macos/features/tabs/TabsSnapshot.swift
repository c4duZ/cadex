import CoreGraphics
import Foundation

/// What a window's tabs are, in a form that can be saved and rebuilt
/// (docs/spec/spaces.md): the order, each tab's panes (a terminal by its
/// folder, a document by its identity) with their proportions, and the
/// active tab. Not the terminals' content: each pane starts a new shell.
public struct TabsSnapshot: Codable, Equatable, Sendable {
    public indirect enum Layout: Codable, Equatable, Sendable {
        /// A terminal pane.
        case pane(folder: String)
        /// A document pane, made again by the app from its identity (a
        /// path, "history:<repo>"). Plan 8, 2026-10-19.
        case document(identity: String)
        /// `sideBySide`: ⌘D's split; otherwise one above the other.
        case split(sideBySide: Bool, ratio: Double, first: Layout, second: Layout)

        /// The terminal panes' folders in reading order.
        public var folders: [String] {
            leaves.compactMap { if case .pane(let folder) = $0 { folder } else { nil } }
        }

        /// The panes (`.pane` and `.document`) in reading order.
        public var leaves: [Layout] {
            switch self {
            case .pane, .document: [self]
            case .split(_, _, let a, let b): a.leaves + b.leaves
            }
        }
    }

    public enum Item: Codable, Equatable, Sendable {
        /// Any tab, terminals and documents alike (the name stays for the
        /// JSON). `focus`: the focused pane's position in reading order.
        /// `color`: a work color's name ("red"), plan 15, phase D.
        case terminal(title: String?, layout: Layout, focus: Int, color: String? = nil)
        /// A document tab as plan 7 saved it (before documents went into
        /// panes): read as a tab with that one pane, never written.
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
    /// The layout of this tree, each pane as `pane` describes it.
    func snapshot(pane: (Int) -> TabsSnapshot.Layout) -> TabsSnapshot.Layout {
        switch self {
        case .leaf(let id):
            return pane(id)
        case .split(let axis, let a, let b, let ratio):
            return .split(sideBySide: axis == .horizontal, ratio: Double(ratio),
                          first: a.snapshot(pane: pane), second: b.snapshot(pane: pane))
        }
    }

    /// The tree of a saved layout, numbering its panes with `nextPane`
    /// (each call gives a new id), in reading order.
    static func from(_ layout: TabsSnapshot.Layout, nextPane: () -> Int) -> PaneTree {
        switch layout {
        case .pane, .document:
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
