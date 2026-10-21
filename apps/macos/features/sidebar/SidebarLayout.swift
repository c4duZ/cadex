import Foundation

/// Which icons the sidebar shows and in what order (docs/spec/sidebar.md):
/// sidebar.items in settings.json is the list, in order; an id left out is
/// hidden. Pure, so the rules are tested without a window.
public enum SidebarLayout {
    /// Files, Search, Git, Agents and Accounts (plan 17).
    public static let defaultItems = ["files", "search", "git", "agents", "accounts"]

    /// The saved list against the ids the app knows: unknown and repeated
    /// ids are dropped, each one noted.
    public static func shown(_ saved: [String], known: [String]) -> (ids: [String], problems: [String]) {
        var ids: [String] = []
        var problems: [String] = []
        for id in saved {
            if !known.contains(id) {
                problems.append("sidebar.items: \"\(id)\" is not a sidebar page")
            } else if ids.contains(id) {
                problems.append("sidebar.items: \"\(id)\" is listed twice")
            } else {
                ids.append(id)
            }
        }
        return (ids, problems)
    }

    /// Shows a hidden id (at the end) or hides a shown one.
    public static func toggled(_ ids: [String], _ id: String) -> [String] {
        ids.contains(id) ? ids.filter { $0 != id } : ids + [id]
    }

    /// The list with `id` moved to `index` (clamped), as a drag drops it.
    public static func moved(_ ids: [String], _ id: String, to index: Int) -> [String] {
        guard ids.contains(id) else { return ids }
        var rest = ids.filter { $0 != id }
        rest.insert(id, at: min(max(index, 0), rest.count))
        return rest
    }

    /// The catalog in the customize list's order: the shown ones first, as
    /// they are, then the hidden ones in the catalog's order.
    public static func customizeOrder(shown: [String], known: [String]) -> [String] {
        shown + known.filter { !shown.contains($0) }
    }

    /// How many icons fit in `width`, leaving room for the "…" button when
    /// some do not.
    public static func fitting(_ count: Int, iconWidth: CGFloat, spacing: CGFloat, width: CGFloat) -> Int {
        func need(_ n: Int) -> CGFloat { n == 0 ? 0 : CGFloat(n) * iconWidth + CGFloat(n - 1) * spacing }
        if need(count) <= width { return count }
        var n = count
        while n > 0 && need(n + 1) > width { n -= 1 }
        return n
    }
}
