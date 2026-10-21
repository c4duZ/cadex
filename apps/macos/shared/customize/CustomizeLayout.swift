import Foundation
import Icons

/// One line of a Customize window: a thing to show or hide and drag into
/// place (a sidebar page, a status bar item).
public struct CustomizeRow: Equatable, Sendable {
    public let id: String
    public let icon: Icon?
    public let title: String
    /// A quieter line under the title ("every 2 s").
    public let subtitle: String?
    /// Lined up on the right, before the switch: a shortcut.
    public let trailing: String?
    public var on: Bool

    public init(id: String, icon: Icon? = nil, title: String, subtitle: String? = nil, trailing: String? = nil, on: Bool) {
        self.id = id
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.on = on
    }
}

/// The window's list: section titles and rows, in order. A row belongs to
/// the section above it, so dragging it past a title moves it there (the
/// status bar's Left and Right).
public enum CustomizeEntry: Equatable, Sendable {
    case header(String)
    case row(CustomizeRow)

    public var row: CustomizeRow? {
        if case .row(let row) = self { return row }
        return nil
    }
}

/// The rules of the list, pure so they are tested without a window.
public enum CustomizeLayout {
    /// The rows under each title, in order; rows before any title make a
    /// section of their own.
    public static func sections(_ entries: [CustomizeEntry]) -> [[CustomizeRow]] {
        var sections: [[CustomizeRow]] = []
        for entry in entries {
            switch entry {
            case .header: sections.append([])
            case .row(let row):
                if sections.isEmpty { sections.append([]) }
                sections[sections.count - 1].append(row)
            }
        }
        return sections
    }

    /// The list with entry `from` moved to `to`; a row never goes above the
    /// first title, which stays first.
    public static func moved(_ entries: [CustomizeEntry], from: Int, to: Int) -> [CustomizeEntry] {
        guard entries.indices.contains(from), entries[from].row != nil else { return entries }
        var list = entries
        let entry = list.remove(at: from)
        let floor = list.first.map { if case .header = $0 { return 1 } else { return 0 } } ?? 0
        list.insert(entry, at: min(max(to, floor), list.count))
        return list
    }

    /// The list with a row's switch flipped.
    public static func flipped(_ entries: [CustomizeEntry], _ id: String) -> [CustomizeEntry] {
        entries.map { entry in
            guard var row = entry.row, row.id == id else { return entry }
            row.on.toggle()
            return .row(row)
        }
    }

    /// Where a dragged thing lands: the slot under `x` (its middle), given
    /// each slot's length and the space between them. Comparing with each
    /// slot's middle instead moved Files two slots for one and left it under
    /// its neighbour (owner's test, 2026-10-21).
    public static func dropIndex(at x: CGFloat, widths: [CGFloat], spacing: CGFloat) -> Int {
        var edge: CGFloat = 0
        for (index, width) in widths.enumerated() {
            if x < edge + width + spacing / 2 { return index }
            edge += width + spacing
        }
        return max(widths.count - 1, 0)
    }
}
