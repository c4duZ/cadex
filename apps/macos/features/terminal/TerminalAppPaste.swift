import AppKit

/// Text and images another feature hands to the program in this terminal
/// (the preview's picked elements, docs/spec/preview.md): pasted as ⌘V
/// would, bracketed and without Enter, but without asking.
extension TerminalView {
    /// The text, then each image's path on its own, as ⌘V pastes an image:
    /// an agent shows "[Image #N]" for it, which this terminal links to the
    /// file (hover shows it, a click opens it). False, and nothing typed,
    /// when there is no session or the text could run commands unseen
    /// (several lines into a program without bracketed paste): the caller
    /// falls back to the clipboard.
    public func pasteFromApp(_ text: String, images: [URL] = []) -> Bool {
        guard let session, !text.isEmpty, session.isPasteSafe(text) else { return false }
        session.paste(text)
        for image in images {
            session.paste(TerminalSession.quotePaths([image.path]))
            notePastedImage(image)
        }
        return true
    }
}
