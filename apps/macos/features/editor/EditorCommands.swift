import CommandPalette

/// The editor's commands (ADR 0005), acting on the editor of the active
/// tab. ⌘F is edit.find, shared with the terminal.
public enum EditorCommands {
    @MainActor
    public static func all(_ active: @escaping @MainActor () -> EditorDocument?) -> [Command] {
        func needsEditor() -> String? { active() == nil ? "Nenhum arquivo aberto no editor" : nil }
        return [
            Command(id: "editor.save", title: "Salvar arquivo", keywords: ["save", "gravar"], category: .file,
                    defaultShortcut: "cmd+s", action: .run { active()?.save() }, unavailableReason: needsEditor),
            Command(id: "editor.fold-all", title: "Dobrar todos os blocos", keywords: ["fold", "recolher"],
                    category: .view, action: .run { active()?.foldAll() }, unavailableReason: needsEditor),
            Command(id: "editor.unfold-all", title: "Desdobrar todos os blocos", keywords: ["unfold", "expandir"],
                    category: .view, action: .run { active()?.unfoldAll() }, unavailableReason: needsEditor),
        ]
    }
}
