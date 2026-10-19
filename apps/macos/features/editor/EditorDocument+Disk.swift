import AppKit

/// Saving, closing with unsaved changes, going to a line, and following
/// the file on disk (docs/spec/editor.md, "Editar" and "Disco").
extension EditorDocument {
    /// ⌘S. False (with the reason in the banner) when it could not save.
    @discardableResult
    public func save() -> Bool {
        guard let textView else { return false }
        guard !readOnly else {
            banner.show("Este arquivo está aberto só para leitura.")
            return false
        }
        let data = Data(textView.string.utf8)
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
        alert.messageText = "Salvar as mudanças em \(title)?"
        alert.informativeText = "Sem salvar, as mudanças se perdem."
        alert.addButton(withTitle: "Salvar")
        alert.addButton(withTitle: "Não salvar")
        alert.addButton(withTitle: "Cancelar").keyEquivalent = "\u{1B}"
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
        guard let textView, let highlighter else { return }
        let index = max(0, min(line - 1, highlighter.lines.count - 1))
        let range = highlighter.lines.range(lines: index, through: index)
        textView.setSelectedRange(NSRange(location: range.location, length: 0))
        textView.scrollRangeToVisible(range)
        if let frame = textView.currentLineFrame(), let clip = textView.enclosingScrollView?.contentView {
            let y = max(0, frame.midY - clip.bounds.height / 2)
            clip.scroll(to: NSPoint(x: 0, y: y))
            textView.enclosingScrollView?.reflectScrolledClipView(clip)
        }
    }

    /// The file's folder changed on disk: if the file itself changed, take
    /// the new text when there is nothing unsaved, otherwise ask.
    public func diskMayHaveChanged() {
        switch EditorFile.read(path) {
        case let .text(text, data, _, _):
            guard data != diskDataForComparison else { return }
            if hasUnsavedChanges {
                banner.show("O arquivo mudou no disco.", actions: [
                    ("Recarregar", { [weak self] in self?.replaceText(text, data: data) }),
                    ("Manter o meu", { [weak self] in self?.keepMine(data) }),
                ])
            } else {
                replaceText(text, data: data)
            }
        case .failed:
            banner.show("O arquivo foi apagado do disco. Salvar cria de novo.")
        case .binary:
            break
        }
    }

    /// New text from disk, keeping the cursor and the scroll where they were.
    func replaceText(_ text: String, data: Data) {
        guard let textView else { return }
        let selection = textView.selectedRange()
        let origin = textView.enclosingScrollView?.contentView.bounds.origin ?? .zero
        replaceAllText(text)
        markSaved(data)
        let length = (text as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        textView.enclosingScrollView?.contentView.scroll(to: origin)
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
