import AppKit

/// What a non-terminal tab shows: a file in the editor, an image, a web
/// page. The feature that owns it implements this; the tabs only place,
/// title and close it (docs/spec/tabs.md).
@MainActor
public protocol TabDocument: AnyObject {
    var view: NSView { get }
    /// The tab's title ("render.zig").
    var title: String { get }
    /// What makes two documents the same (the file path): opening it again
    /// selects the tab it already has.
    var identity: String { get }
    /// Shows a dot in the title and makes closing ask.
    var hasUnsavedChanges: Bool { get }
    /// The document changed its title or unsaved state.
    var onChange: (() -> Void)? { get set }
    /// The tab became active: give the keyboard to the right view.
    func focus()
    /// Asks what to do with unsaved changes, if any, then calls `close`
    /// (not called when the user cancels).
    func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void)
    /// The tab is gone: stop watching, free resources.
    func close()
}
