import AppKit
import StateGlyph
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

    /// A page alone in its tab (a project's, the automations, the board): it opens under the bar
    /// and never shows in it (plan 34 A; the owner, 2026-11-18: opening a page changed the bar).
    func isPageTab(_ tab: Tab) -> Bool { tab.panes.count == 1 && tab.focused.document?.isPage == true }

    /// The group the bar shows (a task's folder, or "" for the project's own tabs); nil without
    /// grouping or tabs. The sidebar lights the place by it (plan 38).
    public var currentGroup: String? { barAnchor.flatMap(group(of:)) }

    /// The active tab is a page.
    public var showsPage: Bool { activeTab.map(isPageTab) ?? false }

    /// The tab the bar is about: the active one, or with a page the terminal tab used last.
    var barAnchor: Tab? {
        guard let active = activeTab, isPageTab(active) else { return activeTab }
        return list.recent.lazy.compactMap { self.tabs[$0] }.first { !self.isPageTab($0) }
    }

    /// The tabs the bar shows, in order: those of the anchor's group, never a page.
    var shownIDs: [Int] {
        let notPages = list.order.filter { id in tabs[id].map { !isPageTab($0) } ?? false }
        guard groupOf != nil, let anchor = barAnchor else { return notPages }
        let key = group(of: anchor)
        return notPages.filter { id in tabs[id].map { group(of: $0) == key } ?? false }
    }

    /// Back from a page to the terminal tab used before it (Esc on a page); the page stays open
    /// behind, the one page there is.
    public func leavePage() {
        guard showsPage, let anchor = barAnchor else { return }
        select(anchor.id)
    }

    /// One page at a time: opening one closes the others (they hold nothing unsaved).
    func closeOtherPages(than kept: Int) {
        for id in list.order where id != kept {
            if let tab = tabs[id], isPageTab(tab) { remove(id) }
        }
    }

    /// The items the bar ends with for the shown group (a task's "Review"), those not open
    /// already; each runs its command. None with a page.
    var extraItems: [TabsExtra] {
        guard !showsPage, let active = activeTab, let extras = extrasOf?(group(of: active) ?? "") else { return [] }
        let open = shownIDs.flatMap { id in tabs[id]?.documents.map(\.identity) ?? [] }
        return extras.filter { extra in !open.contains { $0.hasPrefix(extra.identity) } }
    }

    /// The ids of the tabs in the bar, in order (a test instance logs them after a drag).
    public var barOrder: [Int] { bar.items.map(\.id) }

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
    /// Set: the item goes to that group's tabs instead of running a command (a task's item in the
    /// project's bar, "‹ project" in a task's; plan 36 phase D). "" is the project's own.
    public var group: String?
    /// A task's state, drawn before its name.
    public var state: GlyphState?
    /// Before the tabs ("‹ project"), not after them.
    public var leading = false
    public init(title: String, command: String, identity: String, group: String? = nil, state: GlyphState? = nil, leading: Bool = false) {
        self.title = title
        self.command = command
        self.identity = identity
        self.group = group
        self.state = state
        self.leading = leading
    }
}

/// The extra items' ids in the bar: below any tab's.
let extraItemBase = -100
