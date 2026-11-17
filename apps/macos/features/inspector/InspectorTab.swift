import AppKit
import Icons

/// A button of a tab's header row: the command it runs, its icon and its tip (also its line in
/// the "⋯" menu).
public struct InspectorAction {
    public let command: String
    public let icon: Icon
    public let tip: String
    public init(_ command: String, _ icon: Icon, _ tip: String) {
        self.command = command
        self.icon = icon
        self.tip = tip
    }
}

/// What the scope row says for a tab (docs/spec/inspector.md, "Linha de contexto"): the folder in
/// Files, the branch in Changes (its click switches branch), the project's memory in Memory.
public struct InspectorScope: Equatable {
    public let text: String
    public let command: String?
    public let tip: String?
    public init(_ text: String, command: String? = nil, tip: String? = nil) {
        self.text = text
        self.command = command
        self.tip = tip
    }
}

/// One tab of the right panel: a feature's page that the app passes in (this feature knows none
/// of them), the command its tab runs (ADR 0005: the click opens the panel on it by that command,
/// as ⌘K does), and its header's buttons.
@MainActor
public struct InspectorTab {
    /// Stable, in English: "changes", "files", "history", "memory". Saved in inspector.tab.
    public let id: String
    public let title: String
    /// git.show, explorer.focus, git.show-history, memory.show.
    public let command: String
    public let view: NSView
    /// The header's buttons, in order; past InspectorView.maxShown they go under "⋯", then `more`.
    public let actions: [InspectorAction]
    public let more: [InspectorAction]

    public init(id: String, title: String, command: String, view: NSView,
                actions: [InspectorAction] = [], more: [InspectorAction] = []) {
        self.id = id
        self.title = title
        self.command = command
        self.view = view
        self.actions = actions
        self.more = more
    }
}
