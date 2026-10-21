import AppKit
import Strings
import TempImages

/// Pasted images become PNG files the shell can point to, in
/// <temporary directory>/cadex-paste/ (docs/plans/1-terminal.md).
extension TempImageStore {
    static let pastes = TempImageStore(folder: "cadex-paste", prefix: "paste")
}

/// ⌘V and dropping files on the terminal. What to paste comes from
/// PasteContent; encoding (bracketed paste) and escaping paths are the
/// core's job.
extension TerminalView {

    func pasteFromClipboard() {
        guard let session, let content = PasteContent.read(from: .general) else { return }
        switch content {
        case .files(let urls):
            session.paste(TerminalSession.quotePaths(urls.map(\.path)))
        case .image(let png):
            guard let url = try? TempImageStore.pastes.save(TempImageStore.fitted(png)) else {
                NSSound.beep()
                return
            }
            session.paste(TerminalSession.quotePaths([url.path]))
            notePastedImage(url)
        case .text(let text):
            pasteText(text)
        }
    }

    private func pasteText(_ text: String) {
        guard let session else { return }
        // Ask before pasting several lines into a program without bracketed
        // paste, where a shell would run each line.
        let asks = TerminalPreferences.current.confirmMultilinePaste
        guard asks, !session.isPasteSafe(text), let window else {
            session.paste(text)
            return
        }
        let alert = NSAlert()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        alert.messageText = lines > 1 ? T("Paste \(lines) lines?", "Colar \(lines) linhas?") : T("Paste this text?", "Colar este texto?")
        alert.informativeText = T("The running program does not mark pastes: each line may run as a command.", "O programa em execução não marca colagens: cada linha pode rodar como um comando.")
        alert.addButton(withTitle: T("Paste", "Colar"))
        // NSAlert gives Esc only to a button titled "Cancel" in English.
        alert.addButton(withTitle: T("Cancel", "Cancelar")).keyEquivalent = "\u{1B}"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = T("Don't ask again", "Não perguntar de novo")
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                if alert.suppressionButton?.state == .on {
                    TerminalPreferences.current.confirmMultilinePaste = false
                }
                if response == .alertFirstButtonReturn { self?.session?.paste(text) }
            }
        }
    }

    // MARK: Dropping files

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFiles(sender).isEmpty ? [] : .copy
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedFiles(sender)
        guard let session, !urls.isEmpty else { return false }
        session.paste(TerminalSession.quotePaths(urls.map(\.path)))
        window?.makeFirstResponder(self)
        return true
    }

    private func droppedFiles(_ sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }
}
