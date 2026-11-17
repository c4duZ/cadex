import AppKit
import Preview
import Strings
import Tabs
import Terminal

/// Where an element picked in a preview goes (docs/spec/preview.md,
/// "Escolher elemento"): pasted into the agent's terminal, without Enter,
/// which then takes the keyboard; or the clipboard, when asked (⌥, the
/// setting) or when no terminal runs an agent that takes a safe paste.
@MainActor
enum ElementPickDelivery {
    /// `driving`: the terminal of the agent that drives this preview (plan
    /// 20, Design Mode): of the terminals, it gets the picks first. ⌥ and
    /// the setting still copy: the owner asked for that.
    static func deliver(_ delivery: PickDelivery, tabs: TabsController?, toClipboard: Bool, driving: TerminalView? = nil) -> PickOutcome {
        if delivery.toClipboard || toClipboard { return copy(delivery.text(), note: nil) }
        // The source path from the agent's folder, which it works in. Each element goes as a file
        // the agent reads by its `@` mention (PickFiles, the owner's choice of 2026-11-17: one
        // short line in the box, the picture's path inside); if the file cannot be written, the
        // block and its picture are pasted as before.
        for terminal in [driving].compactMap({ $0 }) + (tabs?.agentTerminals ?? []) {
            if let mention = PickFiles.mention(delivery, relativeTo: terminal.currentDirectory) {
                guard terminal.pasteFromApp(mention, images: []) else { continue }
                tabs?.focus(terminal)
                let title = terminal.programTitle
                return .pasted(into: title.isEmpty ? T("the terminal", "o terminal") : title)
            }
            let pieces = delivery.pieces(relativeTo: terminal.currentDirectory)
            guard let first = pieces.first,
                  terminal.pasteFromApp(first.text, images: first.picture.map { [$0] } ?? []) else { continue }
            for piece in pieces.dropFirst() {
                _ = terminal.pasteFromApp(piece.text, images: piece.picture.map { [$0] } ?? [])
            }
            tabs?.focus(terminal)
            let title = terminal.programTitle
            return .pasted(into: title.isEmpty ? T("the terminal", "o terminal") : title)
        }
        return copy(delivery.text(), note: T("Copied — no agent running", "Copiado — nenhum agente rodando"))
    }

    private static func copy(_ text: String, note: String?) -> PickOutcome {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return .copied(note: note)
    }
}
