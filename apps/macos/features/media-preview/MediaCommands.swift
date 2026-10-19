import CommandPalette

/// The media commands (ADR 0005): zoom of the image or PDF in the active
/// tab. Without one, the keys go on to the focused view.
public enum MediaCommands {
    @MainActor
    public static func all(_ active: @escaping @MainActor () -> MediaDocument?) -> [Command] {
        func zoomable() -> String? {
            guard let doc = active(), doc.kind == .image || doc.kind == .pdf else { return "Nenhuma imagem ou PDF aberto" }
            return nil
        }
        return [
            Command(id: "media.zoom-in", title: "Aumentar o zoom", keywords: ["zoom", "ampliar"], category: .view,
                    defaultShortcut: "cmd+=", action: .run { active()?.zoomIn() }, unavailableReason: zoomable),
            Command(id: "media.zoom-out", title: "Diminuir o zoom", keywords: ["zoom", "reduzir"], category: .view,
                    defaultShortcut: "cmd+-", action: .run { active()?.zoomOut() }, unavailableReason: zoomable),
            Command(id: "media.zoom-fit", title: "Ajustar à aba", keywords: ["zoom", "fit", "caber"], category: .view,
                    defaultShortcut: "cmd+0", action: .run { active()?.zoomToFit() }, unavailableReason: zoomable),
            Command(id: "media.zoom-actual", title: "Tamanho real", keywords: ["zoom", "100%", "original"], category: .view,
                    defaultShortcut: "cmd+opt+0", action: .run { active()?.actualSize() }, unavailableReason: zoomable),
        ]
    }
}
