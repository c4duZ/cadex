import AppKit
import Strings
import Terminal

/// The title bar shows the tabs of where you are (plan 29's review against the Main mockup): a
/// task's tabs and "Review" while a task's tab is active, the project's own otherwise. The app
/// says which group a folder belongs to (`groupOf`: a task's worktree, else the project); the tabs
/// stay one list underneath, and ⌘1…⌘9 and dragging count the shown ones.
extension TabsController {
    /// The folder a tab is about: its focused terminal's, or its document's (a review's repository,
    /// a file's folder).
    func folder(of tab: Tab) -> String? {
        if let terminal = tab.focused.terminal { return terminal.currentDirectory }
        guard let identity = tab.focused.document?.identity else { return nil }
        // A page of the app (a project's, the history): its identity is its group's key.
        if ["project:", "cadex:", "automation:"].contains(where: identity.hasPrefix) { return identity }
        if identity.hasPrefix("review:") {
            return String(identity.dropFirst("review:".count).split(separator: "…", maxSplits: 1).first ?? "")
        }
        return identity.hasPrefix("/") ? (identity as NSString).deletingLastPathComponent : nil
    }

    /// The group of a tab; nil without grouping (no `groupOf`).
    func group(of tab: Tab) -> String? {
        guard let groupOf else { return nil }
        return groupOf(folder(of: tab))
    }

    /// The tabs the bar shows, in order: those of the active tab's group.
    var shownIDs: [Int] {
        guard groupOf != nil, let active = activeTab else { return list.order }
        let key = group(of: active)
        return list.order.filter { id in tabs[id].map { group(of: $0) == key } ?? false }
    }

    /// The items the bar ends with for the shown group (a task's "Review", a project page's
    /// "Automations" and "Conversations"), those not open already; each runs its command.
    var extraItems: [TabsExtra] {
        guard let active = activeTab, let extras = extrasOf?(group(of: active) ?? "") else { return [] }
        let open = shownIDs.flatMap { id in tabs[id]?.documents.map(\.identity) ?? [] }
        return extras.filter { extra in !open.contains { $0.hasPrefix(extra.identity) } }
    }

    /// The bar again (the app learned which folders are tasks).
    public func refreshTabBar() { refreshBar() }

    /// A move in the bar (an index among the shown tabs) placed in the whole list.
    func moveShown(_ id: Int, to index: Int) {
        let shown = shownIDs.filter { $0 != id }
        let target = index < shown.count ? list.order.firstIndex(of: shown[index]) : list.order.firstIndex(of: shown.last ?? id).map { $0 + 1 }
        guard var place = target else { return }
        if let from = list.order.firstIndex(of: id), from < place { place -= 1 }
        list.move(id, to: place)
    }
}

/// An item at the end of the bar that runs a command (it opens a tab whose identity starts with
/// `identity`, and then the tab shows instead).
public struct TabsExtra: Sendable {
    public var title: String
    public var command: String
    public var identity: String
    public init(title: String, command: String, identity: String) {
        self.title = title
        self.command = command
        self.identity = identity
    }
}

/// The extra items' ids in the bar: below any tab's.
let extraItemBase = -100
