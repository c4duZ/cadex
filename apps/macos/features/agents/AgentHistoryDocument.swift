import AppKit
import Strings
import Tabs

/// "Archive & history" in the center, as a tab (plan 27 phase C; it was the sidebar's History
/// page): every conversation of every account, with the same actions (resume, continue in another
/// account, copy the command, reveal). One tab: opening it again selects it. The page reads only
/// while its tab shows, as it did in the sidebar.
@MainActor
public final class AgentHistoryDocument: TabDocument {
    public static let identity = "cadex:agent-history"
    public let view: NSView
    public var title: String { T("Archive & History", "Arquivo e histórico") }
    public var identity: String { Self.identity }
    public var hasUnsavedChanges: Bool { false }
    public var onChange: (() -> Void)?

    public init(page: AgentHistoryView) {
        view = page
    }

    public func focus() { view.window?.makeFirstResponder(view) }

    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }

    public func close() {}
}
