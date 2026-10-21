import AppKit

/// Text another feature hands to the program in this terminal (the
/// preview's picked element, docs/spec/preview.md): pasted as ⌘V would,
/// bracketed and without Enter, but without asking.
extension TerminalView {
    /// False, and nothing typed, when there is no session or the paste
    /// could run commands unseen (several lines into a program without
    /// bracketed paste): the caller falls back to the clipboard.
    public func pasteFromApp(_ text: String) -> Bool {
        guard let session, !text.isEmpty, session.isPasteSafe(text) else { return false }
        session.paste(text)
        return true
    }
}
