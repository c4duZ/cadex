import AppKit
import Menus
import Strings
import UILooks

/// The bar's two places to go (plan 36 phase D; docs/adr/0038-rail-and-side-column.md): a group's
/// tabs (a task's item in the project's bar, "‹ project" in a task's), and the tabs that do not fit,
/// under "» N" at the end, chosen from a list.
extension TabsController {
    /// The id of "» N" in the bar.
    static let overflowItem = extraItemBase - 50

    /// Shows a group's tabs: the one used last in it.
    public func enterGroup(_ key: String) {
        let ids = list.recent + list.order
        guard let id = ids.first(where: { id in tabs[id].map { !isPageTab($0) && group(of: $0) == key } ?? false }) else { return }
        select(id)
    }

    /// How many tabs fit the room the title bar gives, beside the extras, at the narrowest a tab
    /// goes; nil when all fit at their own width (or before the room is known).
    private func capacity(_ shown: [Int], extras: [TabBarView.Item]) -> Int? {
        let room = bar.room
        guard room > 0 else { return nil }
        let gap = UILooks.pt(DesignTokens.Tab.groupGap)
        let tabs = shown.compactMap { self.tabs[$0].map(barItem) }
        let natural = (tabs + extras).map(bar.naturalWidth).reduce(0, +) + gap * CGFloat(tabs.count + extras.count)
        guard natural > room else { return nil }
        let more = bar.naturalWidth(TabBarView.Item(id: Self.overflowItem, title: "» 99", active: false)) + gap
        let left = room - extras.map(bar.naturalWidth).reduce(0, +) - gap * CGFloat(extras.count) - more
        return max(Int(left / (UILooks.pt(DesignTokens.Tab.minWidth) + gap)), 1)
    }

    /// The shown tabs that fit, the active always among them, and those that went under "» N".
    func fitting(_ shown: [Int], extras: [TabBarView.Item]) -> (visible: [Int], hidden: [Int]) {
        guard let room = capacity(shown, extras: extras), shown.count > room else { return (shown, []) }
        var visible = Array(shown.prefix(room))
        if let active = list.active, shown.contains(active), !visible.contains(active) {
            visible[visible.count - 1] = active
        }
        return (visible, shown.filter { !visible.contains($0) })
    }

    /// The bar's items: "‹ project", the tabs that fit, "» N", the extras at the end.
    func barItems() -> [TabBarView.Item] {
        let extras = extraItems
        let item = { (index: Int, extra: TabsExtra) in
            TabBarView.Item(id: extraItemBase - index, title: extra.title, active: false, state: extra.state)
        }
        let leading = extras.enumerated().filter { $0.element.leading }.map { item($0.offset, $0.element) }
        let trailing = extras.enumerated().filter { !$0.element.leading }.map { item($0.offset, $0.element) }
        let (visible, hidden) = fitting(shownIDs, extras: leading + trailing)
        overflowHidden = hidden
        // The chip carries the most urgent state of the hidden tabs: an agent asking for permission
        // behind "» 3" was invisible (UX audit, 2026-11-18).
        let urgent = hidden.compactMap { id in tabs[id].flatMap { barItem($0).state } }.min { $0.urgency < $1.urgency }
        let more = hidden.isEmpty ? [] : [TabBarView.Item(id: Self.overflowItem, title: "» \(hidden.count)", active: false,
                                                          tip: T("\(hidden.count) more tabs", "Mais \(hidden.count) abas")
                                                              + (urgent.map { " · " + $0.words } ?? ""), state: urgent)]
        return leading + visible.compactMap { id in tabs[id].map(barItem) } + more + trailing
    }

    /// "» N" clicked: the tabs that did not fit, to choose one.
    func showOverflow() {
        guard let index = bar.items.firstIndex(where: { $0.id == Self.overflowItem }) else { return }
        let frame = bar.frame(at: index)
        PopupMenu.show(overflowHidden.compactMap { id in
            tabs[id].map { tab in
                // Each hidden tab with its state in words, the urgent ones first to see.
                let state = barItem(tab).state
                return MenuEntry(tab.title(home: home) + (state.map { "  ·  " + $0.words } ?? "")) { [weak self] in self?.select(id) }
            }
        }, at: NSPoint(x: frame.minX, y: frame.maxY), in: bar)
    }
}
