import AppKit
import CommandPalette
import Strings

/// review.toggle-authorship and review.export-authorship (docs/spec/review.md,
/// Autoria; ADR 0005): what each acts on comes from the app.
public enum ReviewAuthorshipCommands {
    @MainActor
    public static func all(toggle: @escaping @MainActor () -> Void, export: @escaping @MainActor () -> Void,
                           canToggle: @escaping @MainActor () -> String?, canExport: @escaping @MainActor () -> String?) -> [Command] {
        [
            Command(id: "review.toggle-authorship", title: T("Show or Hide Who Wrote Each Line", "Mostrar ou esconder quem escreveu cada linha"),
                    keywords: ["authorship", "agent", "blame", "autoria", "agente"], category: .view,
                    action: .run { toggle() }, unavailableReason: canToggle),
            Command(id: "review.export-authorship", title: T("Export Line Authorship…", "Exportar a autoria das linhas…"),
                    keywords: ["authorship", "export", "json", "autoria", "exportar"], category: .file,
                    action: .run { export() }, unavailableReason: canExport),
        ]
    }
}
