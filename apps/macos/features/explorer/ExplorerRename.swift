import AppKit

/// Renaming in place: Enter (or leaving the field) renames through the
/// core, Esc puts the old name back. A refused name keeps the file as it
/// was and says why under the tree (docs/spec/explorer.md).
extension ExplorerController: NSTextFieldDelegate {
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)), let node = renaming else { return false }
        renaming = nil
        (control as? NSTextField)?.stringValue = node.name
        (control as? NSTextField)?.abortEditing()
        finishRename(control)
        redrawRow(of: node)
        return true
    }

    /// While typing, a name that would be refused turns the field red (as
    /// CodeEdit does): empty, with "/", or a sibling's.
    public func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let node = renaming else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let siblings = parentFolder(of: node).children ?? []
        let taken = name != node.name && siblings.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        let refused = name.isEmpty || name.contains("/") || taken
        field.drawsBackground = refused
        field.backgroundColor = refused ? NSColor.systemRed.withAlphaComponent(0.25) : .clear
    }

    public func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let node = renaming else { return }
        renaming = nil
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        finishRename(field)
        guard name != node.name else { return redrawRow(of: node) }
        guard !name.isEmpty, !name.contains("/") else {
            redrawRow(of: node)
            return showMessage("Nome inválido")
        }
        let parent = parentFolder(of: node)
        do {
            let renamed = try ExplorerFiles.rename(node.path, to: name)
            reload(parent)
            select(path: renamed)
        } catch {
            redrawRow(of: node)
            showMessage(error.message)
        }
    }

    /// The row's text again (a compact row shows the whole chain).
    private func redrawRow(of node: FileNode) {
        let row = self.row(of: node)
        if row >= 0 { outline.reloadData(forRowIndexes: [row], columnIndexes: [0]) }
    }

    private func finishRename(_ control: NSControl) {
        (control as? NSTextField)?.isEditable = false
        (control as? NSTextField)?.drawsBackground = false
        outline.window?.makeFirstResponder(outline)
    }
}
