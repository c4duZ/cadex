import AppKit
import Terminal

/// What a pane shows: a terminal or a document (docs/spec/tabs.md,
/// "Documentos em painéis"). Both split, take focus and close the same way.
@MainActor
enum Pane {
    case terminal(TerminalView)
    case document(TabDocument)

    var view: NSView {
        switch self {
        case .terminal(let terminal): terminal
        case .document(let document): document.view
        }
    }

    var terminal: TerminalView? {
        if case .terminal(let terminal) = self { return terminal }
        return nil
    }

    var document: TabDocument? {
        if case .document(let document) = self { return document }
        return nil
    }

    /// The folder a terminal opened from this pane starts in.
    var folder: String? {
        switch self {
        case .terminal(let terminal): terminal.currentDirectory
        case .document(let document): document.folder
        }
    }
}

extension TabDocument {
    /// The file's folder, for a document that is a file ("/a/b.md").
    var folder: String? {
        identity.hasPrefix("/") ? (identity as NSString).deletingLastPathComponent : nil
    }
}

/// One tab: its panes, how they divide the space, which one has focus, and
/// the name the user gave the tab, if any.
@MainActor
final class Tab {
    let id: Int
    /// Set by "Renomear aba"; stays when the folder changes. Nil shows the
    /// focused pane's folder or document (docs/spec/tabs.md).
    var customTitle: String?
    private(set) var panes: [Int: Pane] = [:]
    private(set) var focusedPane: Int
    let layout = PaneLayoutView(frame: .zero)

    /// A divider was dragged: the saved layout changes (spaces).
    var onLayoutChange: (() -> Void)?

    convenience init(id: Int, pane: Int, content: Pane) {
        self.init(id: id, tree: .leaf(pane), panes: [pane: content], focused: pane)
    }

    /// A tab with panes already laid out (a restored one).
    init(id: Int, tree: PaneTree, panes: [Int: Pane], focused: Int) {
        self.id = id
        focusedPane = focused
        self.panes = panes
        layout.tree = tree
        layout.panes = panes.mapValues(\.view)
        layout.focused = focused
        layout.onTreeChange = { [weak self] tree in
            self?.layout.tree = tree
            self?.onLayoutChange?()
        }
        layout.syncSubviews()
    }

    /// The tab as saved: its name, panes with folders or documents, and focus.
    func snapshot(home: String) -> TabsSnapshot.Item {
        let layout = tree.snapshot { id in
            if let document = panes[id]?.document { return .document(identity: document.identity) }
            return .pane(folder: panes[id]?.terminal?.currentDirectory ?? home)
        }
        return .terminal(title: customTitle, layout: layout, focus: tree.leaves.firstIndex(of: focusedPane) ?? 0)
    }

    var view: NSView { layout }
    var focused: Pane { panes[focusedPane]! }
    var tree: PaneTree { layout.tree }
    /// Panes in reading order.
    var ordered: [Pane] { layout.tree.leaves.compactMap { panes[$0] } }
    var terminals: [TerminalView] { ordered.compactMap(\.terminal) }
    var documents: [TabDocument] { ordered.compactMap(\.document) }

    func title(home: String) -> String {
        let dot = documents.contains { $0.hasUnsavedChanges } ? "● " : ""
        if let customTitle, !customTitle.isEmpty { return dot + customTitle }
        if let document = focused.document { return dot + document.title }
        return dot + folderTitle(focused.terminal?.currentDirectory, home: home)
    }

    var hasForegroundProcess: Bool { terminals.contains { $0.hasForegroundProcess } }
    var unsavedCount: Int { documents.filter(\.hasUnsavedChanges).count }

    func canSplit(axis: PaneTree.Axis) -> Bool {
        layout.canSplit(focusedPane, axis: axis)
    }

    /// Splits the focused pane; the new one takes the focus.
    func split(axis: PaneTree.Axis, pane: Int, content: Pane) {
        layout.tree = layout.tree.splitting(focusedPane, axis: axis, newPane: pane).balanced()
        panes[pane] = content
        layout.panes[pane] = content.view
        layout.syncSubviews()
        focus(pane)
    }

    /// Puts `content` in `pane`'s place, same size and position; the old
    /// content is the caller's to close.
    func replace(pane: Int, with content: Pane) {
        guard panes[pane] != nil else { return }
        panes[pane] = content
        layout.panes[pane] = content.view
        layout.syncSubviews()
    }

    /// Removes a pane; the focus goes to the pane that took its space.
    /// Returns false when it was the last one (the tab is now empty).
    func remove(pane: Int) -> Bool {
        let order = layout.tree.leaves
        guard let rest = layout.tree.removing(pane) else { return false }
        let index = order.firstIndex(of: pane) ?? 0
        panes[pane] = nil
        layout.panes[pane] = nil
        layout.tree = rest.balanced()
        layout.syncSubviews()
        if focusedPane == pane {
            let remaining = rest.leaves
            focus(remaining[min(max(index - 1, 0), remaining.count - 1)])
        }
        return true
    }

    func focus(_ pane: Int) {
        guard let content = panes[pane] else { return }
        noteFocus(pane)
        giveKeyboard(content)
    }

    /// The focused pane takes the keyboard (the tab came into view).
    func focusContent() {
        giveKeyboard(focused)
    }

    private func giveKeyboard(_ content: Pane) {
        switch content {
        case .terminal(let terminal): terminal.window?.makeFirstResponder(terminal)
        case .document(let document): document.focus()
        }
    }

    /// Records that a pane got the focus by itself (a click).
    func noteFocus(_ pane: Int) {
        guard panes[pane] != nil else { return }
        focusedPane = pane
        layout.focused = pane
    }

    /// The pane id of a terminal, for its callbacks.
    func pane(of terminal: TerminalView) -> Int? {
        panes.first { $0.value.terminal === terminal }?.key
    }

    /// The pane id of a document.
    func pane(of document: TabDocument) -> Int? {
        panes.first { $0.value.document === document }?.key
    }

    /// The pane showing the document with this identity.
    func pane(identity: String) -> Int? {
        panes.first { $0.value.document?.identity == identity }?.key
    }
}
