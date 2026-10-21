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
        // The source path from the agent's folder, which it works in.
        for terminal in tabs?.agentTerminals ?? [] where terminal.pasteFromApp(delivery.text(relativeTo: terminal.currentDirectory)) {
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
