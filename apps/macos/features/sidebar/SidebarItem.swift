import AppKit
import Icons

/// One icon of the sidebar's row (docs/spec/sidebar.md). The app fills the
/// catalog with each feature's view, through its entry point; the click
/// runs `command`, as every button does (ADR 0005).
@MainActor
public struct SidebarItem {
    /// A page shows its view in the sidebar; an action only runs its
    /// command (Search opens the palette, History a tab).
    public enum Kind {
        case page(NSView)
        case action
    }

    /// Stable, in English: "files", "git". The value saved in sidebar.items.
    public let id: String
    public let icon: Icon
    public let title: String
    /// The command the click runs: "explorer.focus", "git.show".
    public let command: String
    /// The shortcut as the menus show it ("⇧⌘E"), for the tip.
    public let shortcut: String?
    public let kind: Kind
    /// The page's views, picked under the icons (Agents: Sessions,
    /// Accounts); the page shows the one the app is told.
    public let subtabs: [Subtab]

    public struct Subtab: Equatable, Sendable {
        public let id: String
        public let title: String
        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    /// The page's buttons in the header row, in order; past
    /// SidebarHeader.maxShown they go under "⋯", after them `more`.
    public let actions: [SidebarAction]
    public let more: [SidebarAction]

    public init(id: String, icon: Icon, title: String, command: String, shortcut: String? = nil, kind: Kind, subtabs: [Subtab] = [],
                actions: [SidebarAction] = [], more: [SidebarAction] = []) {
        self.actions = actions
        self.more = more
        self.id = id
        self.icon = icon
        self.title = title
        self.command = command
        self.shortcut = shortcut
        self.kind = kind
        self.subtabs = subtabs
    }

    var view: NSView? {
        if case .page(let view) = kind { return view }
        return nil
    }

    var tip: String { shortcut.map { "\(title) (\($0))" } ?? title }
}
