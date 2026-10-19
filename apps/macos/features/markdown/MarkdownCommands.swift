import CommandPalette
import Editor

/// The markdown commands (ADR 0005), on the note of the active tab.
public enum MarkdownCommands {
    @MainActor
    public static func all(_ markdown: MarkdownController, palette: CommandPaletteController,
                           active: @escaping @MainActor () -> EditorDocument?) -> [Command] {
        func note() -> EditorDocument? {
            guard let doc = active(), MarkdownController.isMarkdown(doc.path) else { return nil }
            return doc
        }
        func needsNote() -> String? { note() == nil ? "Nenhuma nota Markdown aberta" : nil }
        return [
            Command(id: "markdown.toggle-preview", title: "Alternar Markdown renderizado", keywords: ["preview", "renderizar", "visualizar"],
                    category: .view, defaultShortcut: "cmd+shift+v",
                    action: .run { if let doc = note() { markdown.togglePreview(doc) } }, unavailableReason: needsNote),
            Command(id: "markdown.open-link", title: "Abrir o link sob o cursor", keywords: ["link", "seguir", "ir"],
                    category: .file, action: .run { if let doc = note() { markdown.openLink(in: doc) } },
                    unavailableReason: needsNote),
            Command(id: "markdown.backlinks", title: "Quem aponta pra cá", keywords: ["backlinks", "referências", "links"],
                    category: .file, action: .run { if let doc = note() { palette.open(markdown.backlinks(of: doc.path)) } },
                    unavailableReason: needsNote),
        ]
    }
}
