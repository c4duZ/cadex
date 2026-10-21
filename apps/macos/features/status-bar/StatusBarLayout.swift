import Customize
import Foundation
import Strings

/// Which items the status bar shows, on which side and in what order
/// (docs/spec/status-bar.md): statusBar.left and statusBar.right in
/// settings.json; an item in neither is hidden. Pure, so the rules are
/// tested without a window.
public enum StatusBarLayout {
    /// The bar from before it had items: the folder and the environment.
    public static let defaultLeft = ["folder"]
    public static let defaultRight = ["environment"]

    /// The saved sides against the ids the app knows: unknown ids, and an
    /// id listed again (on the same side or the other), are dropped and noted.
    public static func placed(left: [String], right: [String], known: [String]) -> (left: [String], right: [String], problems: [String]) {
        var seen: Set<String> = []
        var problems: [String] = []
        func keep(_ ids: [String], _ key: String) -> [String] {
            ids.filter { id in
                if !known.contains(id) { problems.append("\(key): \"\(id)\" is not a status bar item"); return false }
                if !seen.insert(id).inserted { problems.append("\(key): \"\(id)\" is listed twice"); return false }
                return true
            }
        }
        let l = keep(left, "statusBar.left")
        let r = keep(right, "statusBar.right")
        return (l, r, problems)
    }

    /// Shows a hidden item at the end of its usual side, or hides it.
    public static func toggled(left: [String], right: [String], _ id: String, side: StatusItem.Side) -> (left: [String], right: [String]) {
        if left.contains(id) || right.contains(id) { return (left.filter { $0 != id }, right.filter { $0 != id }) }
        return side == .left ? (left + [id], right) : (left, right + [id])
    }

    /// The Customize window's list: Left and Right, each with its shown
    /// items in order and then the hidden ones whose usual side it is.
    @MainActor
    static func entries(left: [String], right: [String], catalog: [StatusItem]) -> [CustomizeEntry] {
        func rows(_ shown: [String], _ side: StatusItem.Side) -> [CustomizeEntry] {
            let hidden = catalog.filter { $0.side == side && !left.contains($0.id) && !right.contains($0.id) }.map(\.id)
            return (shown + hidden).compactMap { id in
                catalog.first { $0.id == id }.map {
                    .row(CustomizeRow(id: $0.id, icon: $0.icon, title: $0.title, subtitle: $0.subtitle, on: shown.contains($0.id)))
                }
            }
        }
        return [.header(T("Left", "Esquerda"))] + rows(left, .left) + [.header(T("Right", "Direita"))] + rows(right, .right)
    }

    /// The sides back from the window: the rows switched on under each title.
    public static func sides(from entries: [CustomizeEntry]) -> (left: [String], right: [String]) {
        let sections = CustomizeLayout.sections(entries)
        let left = sections.first?.filter(\.on).map(\.id) ?? []
        let right = sections.count > 1 ? sections[1].filter(\.on).map(\.id) : []
        return (left, right)
    }
}
