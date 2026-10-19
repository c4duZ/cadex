import AppKit

/// An action of the app (ADR 0005). Menus, shortcuts, buttons and the
/// palette run commands by id; nothing implements an action on its own.
public struct Command {
    /// Where the command sits in the app menu.
    public enum Category: Int, CaseIterable, Sendable {
        case app, edit, terminal, tabs, panes

        /// The menu title, in Portuguese like the rest of the interface.
        public var title: String {
            switch self {
            case .app: "Cadex"
            case .edit: "Editar"
            case .terminal: "Terminal"
            case .tabs: "Abas"
            case .panes: "Painéis"
            }
        }
    }

    /// What the command does: send an action down the responder chain (so
    /// ⌘C copies from whatever has focus, terminal or text field), or run
    /// code that the owning feature captured.
    public enum Action {
        case responder(Selector)
        case run(@MainActor () -> Void)
    }

    /// Stable, in English, feature-prefixed: "tab.new", "pane.split-right".
    public let id: String
    /// What the palette and the menu show, in Portuguese.
    public let title: String
    /// Extra words the palette search matches ("limpar" also finds "clear").
    public let keywords: [String]
    public let category: Category
    /// The default key combination, as Shortcuts parses it: "cmd+shift+d".
    public let defaultShortcut: String?
    public let action: Action
    /// Nil when the command can run now, otherwise why not (shown greyed
    /// out in the palette). Responder actions are unavailable when nothing
    /// in focus handles them.
    public let unavailableReason: @MainActor () -> String?

    public init(
        id: String, title: String, keywords: [String] = [], category: Category,
        defaultShortcut: String? = nil, action: Action,
        unavailableReason: @escaping @MainActor () -> String? = { nil }
    ) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.category = category
        self.defaultShortcut = defaultShortcut
        self.action = action
        self.unavailableReason = unavailableReason
    }

    /// A command that sends `selector` to the focused responder, unavailable
    /// with `reason` when nothing in focus handles it.
    public static func responder(
        _ id: String, _ title: String, keywords: [String] = [], category: Category,
        shortcut: String? = nil, selector: Selector, reason: String
    ) -> Command {
        Command(id: id, title: title, keywords: keywords, category: category, defaultShortcut: shortcut,
                action: .responder(selector),
                unavailableReason: { NSApplication.shared.target(forAction: selector, to: nil, from: nil) == nil ? reason : nil })
    }
}
