import AppKit
import Preview
import Strings
import Tabs

/// Where an element picked in a preview goes (docs/spec/preview.md,
/// "Escolher elemento"): pasted into the agent's terminal, without Enter,
/// which then takes the keyboard; or the clipboard, when asked (⌥, the
/// setting) or when no terminal runs an agent that takes a safe paste.
@MainActor
enum ElementPickDelivery {
    static func deliver(_ delivery: PickDelivery, tabs: TabsController?, toClipboard: Bool) -> PickOutcome {
        if delivery.toClipboard || toClipboard { return copy(delivery.text(), note: nil) }
        // The source path from the agent's folder, which it works in; each
        // element's picture after its block, as an image the terminal links
        // to its [Image #N] tag.
        for terminal in tabs?.agentTerminals ?? [] {
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
