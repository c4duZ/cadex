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
        return true
    }

    public func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let node = renaming else { return }
        renaming = nil
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        finishRename(field)
        guard name != node.name else { return }
        guard !name.isEmpty, !name.contains("/") else {
            field.stringValue = node.name
            return showMessage("Nome inválido")
        }
        let parent = (outline.parent(forItem: node) as? FileNode) ?? root
        do {
            let renamed = try ExplorerFiles.rename(node.path, to: name)
            reload(parent)
            select(path: renamed)
        } catch {
            field.stringValue = node.name
            showMessage(error.message)
        }
    }

    private func finishRename(_ control: NSControl) {
        (control as? NSTextField)?.isEditable = false
        outline.window?.makeFirstResponder(outline)
    }
}
