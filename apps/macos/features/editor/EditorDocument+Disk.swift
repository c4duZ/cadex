import AppKit
import Strings

/// Saving, closing with unsaved changes, going to a line, and following
/// the file on disk (docs/spec/editor.md, "Editar" and "Disco").
extension EditorDocument {
    /// ⌘S. False (with the reason in the banner) when it could not save.
    @discardableResult
    public func save() -> Bool {
        guard let codeView else { return false }
        guard !readOnly else {
            banner.show(T("This file is open read-only.", "Este arquivo está aberto só para leitura."))
            return false
        }
        let data = Data(codeView.string.utf8)
        if let problem = EditorFile.write(path, data) {
            banner.show(problem)
            return false
        }
        markSaved(data)
        banner.hide()
        return true
    }

    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) {
        guard hasUnsavedChanges, let window else { return close() }
        let alert = NSAlert()
        alert.messageText = T("Save the changes to \(title)?", "Salvar as mudanças em \(title)?")
        alert.informativeText = T("If you don't save, your changes will be lost.", "Sem salvar, as mudanças se perdem.")
        alert.addButton(withTitle: T("Save", "Salvar"))
        alert.addButton(withTitle: T("Don't Save", "Não salvar"))
        alert.addButton(withTitle: T("Cancel", "Cancelar")).keyEquivalent = "\u{1B}"
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                switch response {
                case .alertFirstButtonReturn: if self?.save() == true { close() }
                case .alertSecondButtonReturn: close()
                default: break
                }
            }
        }
    }

    /// Puts the cursor at the start of a 1-based line, centered.
    public func reveal(line: Int) {
        guard let codeView, let highlighter else { return }
        let index = max(0, min(line - 1, highlighter.lines.count - 1))
        let range = highlighter.lines.range(lines: index, through: index)
        codeView.setSelectedRange(NSRange(location: range.location, length: 0))
        codeView.scrollRangeToVisible(range)
        if let frame = codeView.currentLineFrame(), let clip = codeView.enclosingScrollView?.contentView {
            let y = max(0, frame.midY - clip.bounds.height / 2)
            clip.scroll(to: NSPoint(x: 0, y: y))
            codeView.enclosingScrollView?.reflectScrolledClipView(clip)
        }
    }

    /// The file's folder changed on disk: if the file itself changed, take
    /// the new text when there is nothing unsaved, otherwise ask.
    public func diskMayHaveChanged() {
        switch EditorFile.read(path) {
        case let .text(text, data, _, _):
            guard data != diskDataForComparison else { return }
            if hasUnsavedChanges {
                banner.show(T("The file changed on disk.", "O arquivo mudou no disco."), actions: [
                    (T("Reload", "Recarregar"), { [weak self] in self?.replaceText(text, data: data) }),
                    (T("Keep Mine", "Manter o meu"), { [weak self] in self?.keepMine(data) }),
                ])
            } else {
                replaceText(text, data: data)
            }
        case .failed:
            banner.show(T("The file was deleted from disk. Saving creates it again.", "O arquivo foi apagado do disco. Salvar cria de novo."))
        case .binary:
            break
        }
    }

    /// New text from disk, keeping the cursor and the scroll where they were.
    func replaceText(_ text: String, data: Data) {
        guard let codeView else { return }
        let selection = codeView.selectedRange()
        let origin = codeView.enclosingScrollView?.contentView.bounds.origin ?? .zero
        replaceAllText(text)
        markSaved(data)
        let length = (text as NSString).length
        codeView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        codeView.enclosingScrollView?.contentView.scroll(to: origin)
        banner.hide()
    }

    private func keepMine(_ data: Data) {
        // The disk's version is now known: later saves overwrite it.
        markSaved(data, clean: false)
        banner.hide()
    }

    /// edit.fold-all and edit.unfold-all.
    public func foldAll() { folding.foldAll() }
    public func unfoldAll() { folding.unfoldAll() }
}
