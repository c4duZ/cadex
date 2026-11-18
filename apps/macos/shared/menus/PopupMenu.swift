import AppKit
import UILooks
import Icons

/// The app's popup menus (right click, the "+" by the tabs, the status
/// bar's folders) in the look of ⌘K: the theme's colors, icons, rounded
/// selection and shortcuts as keys. The system menu was translucent and
/// plain, apart from the rest of the app (owner, 2026-10-20).
@MainActor
public enum PopupMenu {
    private static var panel: PopupMenuPanel?

    /// Shows `entries` with the top-left corner at `point`, in `view`'s
    /// coordinates; above it when there is no room below.
    public static func show(_ entries: [MenuEntry], at point: NSPoint, in view: NSView, upward: Bool = false,
                            onClose: (@MainActor () -> Void)? = nil) {
        let entries = MenuEntry.tidy(entries)
        guard !entries.isEmpty, let window = view.window else { return }
        panel?.close(running: nil)
        let panel = PopupMenuPanel(entries: entries, parent: window)
        // An action may open another menu before this one's onClose runs.
        panel.onClose = { [weak panel] in
            if Self.panel === panel { Self.panel = nil }
            onClose?()
        }
        self.panel = panel
        let screenPoint = window.convertPoint(toScreen: view.convert(point, to: nil))
        panel.show(at: screenPoint, upward: upward)
    }

    /// Under `view`, its left edges lined up (a button's menu).
    public static func show(_ entries: [MenuEntry], below view: NSView) {
        let y = view.isFlipped ? view.bounds.maxY + 4 : -4
        show(entries, at: NSPoint(x: 0, y: y), in: view)
    }

    /// Over `view`, growing up from its top edge (the status bar's menus,
    /// at the bottom of the window).
    public static func show(_ entries: [MenuEntry], above view: NSView) {
        let y = view.isFlipped ? -4 : view.bounds.maxY + 4
        show(entries, at: NSPoint(x: 0, y: y), in: view, upward: true)
    }

    public static var isOpen: Bool { panel != nil }
}

/// Sizes and keyboard moves, apart from drawing so the tests can check them.
@MainActor
/// The measures of the approved proposal's menu (scratchpad ux2/index.html, `.menu`, 2026-11-18):
/// 6 pt around, rows of 7 pt over and under a 13 pt line, 9 pt in, captions in 11 pt bold spaced
/// capitals, the separator 5 pt from each side, corners of 12 and of 8 on the rows.
enum MenuLayout {
    static var padding: CGFloat { UILooks.pt(6) }
    static var itemHeight: CGFloat { UILooks.rowHeight(32) }
    static var captionHeight: CGFloat { UILooks.rowHeight(24) }
    static var separatorHeight: CGFloat { UILooks.rowHeight(11) }
    static var minWidth: CGFloat { UILooks.pt(300) }
    static var inset: CGFloat { UILooks.pt(9) }
    static var radius: CGFloat { UILooks.pt(12) }
    static var rowRadius: CGFloat { UILooks.pt(8) }
    static var font: NSFont { UILooks.font(13) }
    static var keyFont: NSFont { UILooks.font(11) }
    static var captionFont: NSFont { UILooks.font(11, weight: .bold) }
    static var detailFont: NSFont { UILooks.font(11.5) }

    static func height(of entry: MenuEntry) -> CGFloat {
        entry.isSeparator ? separatorHeight : entry.isCaption ? captionHeight : itemHeight
    }

    /// Each entry's frame, top to bottom, in a flipped view `width` wide.
    static func frames(_ entries: [MenuEntry], width: CGFloat) -> [NSRect] {
        var y = padding
        return entries.map { entry in
            defer { y += height(of: entry) }
            return NSRect(x: padding, y: y, width: width - 2 * padding, height: height(of: entry))
        }
    }

    static func totalHeight(_ entries: [MenuEntry]) -> CGFloat {
        entries.reduce(2 * padding) { $0 + height(of: $1) }
    }

    /// Icon, title, a gap, then the keys.
    static func width(_ entries: [MenuEntry]) -> CGFloat {
        let widest = entries.map { entry -> CGFloat in
            let title = (entry.title as NSString).size(withAttributes: [.font: font]).width
            let keys = entry.shortcut.map { keycapsWidth($0) + 24 } ?? 0
            let detail = entry.detail.map { ($0 as NSString).size(withAttributes: [.font: detailFont]).width + 12 } ?? 0
            let leading = entry.icon == nil && entry.image == nil ? 0 : UILooks.pt(28)
            return 2 * padding + 2 * inset + leading + title + keys + detail + (entry.opensList ? 20 : 0)
        }.max() ?? 0
        return max(minWidth, ceil(widest))
    }

    /// The shortcut in one key ("⌘T"), as the proposal draws it.
    static func keycapsWidth(_ label: String) -> CGFloat {
        ceil((label as NSString).size(withAttributes: [.font: keyFont]).width) + UILooks.pt(10)
    }

    static func keycapWidth(_ key: String) -> CGFloat {
        max(20, ceil((key as NSString).size(withAttributes: [.font: keyFont]).width) + 10)
    }

    /// "⇧⌘D" is ⇧, ⌘ and D, as in the palette.
    static func keys(of label: String) -> [String] {
        let modifiers = label.prefix { "⌃⌥⇧⌘".contains($0) }
        let rest = label.dropFirst(modifiers.count)
        return modifiers.map(String.init) + (rest.isEmpty ? [] : [String(rest)])
    }

    /// The next enabled entry from `index` by `step`, wrapping; nil when
    /// none is enabled.
    static func next(from index: Int?, by step: Int, in entries: [MenuEntry]) -> Int? {
        guard entries.contains(where: { !$0.isSeparator && !$0.isCaption && $0.isEnabled }) else { return nil }
        var candidate = index ?? (step > 0 ? -1 : entries.count)
        repeat {
            candidate = (candidate + step + entries.count) % entries.count
        } while entries[candidate].isSeparator || entries[candidate].isCaption || !entries[candidate].isEnabled
        return candidate
    }
}
