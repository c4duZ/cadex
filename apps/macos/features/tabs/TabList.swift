import Foundation

/// The order of the tabs, which one is active, and the order of use
/// (docs/spec/tabs.md). Pure: ids only, so the rules are testable.
struct TabList: Equatable {
    private(set) var order: [Int] = []
    private(set) var active: Int?
    /// Most recently used first; Ctrl+Tab goes back to the second.
    private(set) var recent: [Int] = []

    /// Adds a tab right after the active one and makes it active.
    mutating func insert(_ id: Int) {
        let at = active.flatMap { order.firstIndex(of: $0) }.map { $0 + 1 } ?? order.count
        order.insert(id, at: at)
        select(id)
    }

    mutating func select(_ id: Int) {
        guard order.contains(id) else { return }
        active = id
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
    }

    /// Removes a tab. If it was active, the one used before it takes over.
    mutating func remove(_ id: Int) {
        order.removeAll { $0 == id }
        recent.removeAll { $0 == id }
        if active == id {
            active = nil
            if let next = recent.first ?? order.first { select(next) }
        }
    }

    /// The tab at a 1-based position (⌘1 to ⌘9), or nil past the end.
    func id(atPosition position: Int) -> Int? {
        position >= 1 && position <= order.count ? order[position - 1] : nil
    }

    /// Ctrl+Tab: the tab used before the current one.
    var previouslyUsed: Int? { recent.count > 1 ? recent[1] : nil }

    /// Ctrl+Shift+Tab: the tab used longest ago.
    var leastRecentlyUsed: Int? { recent.count > 1 ? recent.last : nil }

    /// Drag to reorder: puts the tab at `index` in the order.
    mutating func move(_ id: Int, to index: Int) {
        guard let from = order.firstIndex(of: id) else { return }
        order.remove(at: from)
        order.insert(id, at: min(max(index, 0), order.count))
    }
}

/// The title of a tab from its folder: the last component, "~" for home.
func folderTitle(_ path: String?, home: String) -> String {
    guard let path, !path.isEmpty else { return "~" }
    if path == home { return "~" }
    let name = (path as NSString).lastPathComponent
    return name.isEmpty ? path : name
}
