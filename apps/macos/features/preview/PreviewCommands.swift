import CommandPalette
import Strings

/// The preview's commands (ADR 0005). Reload, back and forward act on the
/// preview of the active tab; without one, ⌘R goes on to the focused view.
public enum PreviewCommands {
    @MainActor
    /// open: a preview for the address ("" a blank one), beside (true), in
    /// a new tab (false) or where the setting says (nil).
    public static func all(open: @escaping @MainActor (String, Bool?) -> Void,
                           active: @escaping @MainActor () -> PreviewDocument?) -> [Command] {
        func needsPreview() -> String? { active() == nil ? T("No preview open", "Nenhum preview aberto") : nil }
        func needsNotes() -> String? { (active()?.noteCount ?? 0) > 0 ? nil : T("No notes on this page", "Nenhuma nota nesta página") }
        func needsPicking() -> String? { active()?.isPicking == true ? nil : T("Not picking an element", "Não está escolhendo elemento") }
        return [
            // ⇧⌘H was the git graph's: the preview is used far more, now
            // that elements are picked in it (owner, 2026-10-21).
            Command(id: "preview.open", title: T("Open Web Preview", "Abrir preview web"), keywords: ["browser", "navegador", "localhost", "site"],
                    category: .view, defaultShortcut: "cmd+shift+h", action: .run { open("", nil) }),
            Command(id: "preview.open-in-tab", title: T("Open Web Preview in New Tab", "Abrir preview web em nova aba"),
                    keywords: ["browser", "navegador", "localhost", "site", "aba"], category: .view, action: .run { open("", false) }),
            Command(id: "preview.reload", title: T("Reload Preview", "Recarregar o preview"), keywords: ["reload", "refresh", "atualizar"], category: .view,
                    defaultShortcut: "cmd+r", action: .run { active()?.reload() }, unavailableReason: needsPreview),
            Command(id: "preview.back", title: T("Go Back in Preview", "Voltar no preview"), keywords: ["back", "previous", "anterior"], category: .view,
                    action: .run { active()?.goBack() }, unavailableReason: needsPreview),
            Command(id: "preview.forward", title: T("Go Forward in Preview", "Avançar no preview"), keywords: ["forward", "next", "próxima"], category: .view,
                    action: .run { active()?.goForward() }, unavailableReason: needsPreview),
            // Mac only for now (docs/adr/0018-element-picker.md).
            Command(id: "preview.pick-element", title: T("Pick Element in Preview", "Escolher elemento no preview"),
                    keywords: ["inspect", "inspecionar", "select", "selecionar", "element", "elemento", "agent", "agente", "copy", "copiar"],
                    category: .view, defaultShortcut: "cmd+shift+c", action: .run { active()?.togglePicking() },
                    unavailableReason: needsPreview),
            // Notes for the agent (plan 20, Design Mode).
            Command(id: "preview.add-note", title: T("Add a Note to the Page", "Pôr uma nota na página"),
                    keywords: ["note", "agent", "design", "nota", "agente"], category: .view,
                    action: .run { active()?.addNote() }, unavailableReason: needsPreview),
            Command(id: "preview.send-notes", title: T("Send the Page's Notes to the Agent", "Mandar as notas da página ao agente"),
                    keywords: ["notes", "agent", "send", "notas", "agente", "mandar"], category: .view,
                    action: .run { active()?.sendNotes() }, unavailableReason: needsNotes),
            Command(id: "preview.clear-notes", title: T("Clear the Page's Notes", "Apagar as notas da página"),
                    keywords: ["notes", "clear", "notas", "apagar"], category: .view,
                    action: .run { active()?.clearNotes() }, unavailableReason: needsNotes),
            Command(id: "preview.stop-picking", title: T("Stop Picking", "Parar de escolher"), keywords: ["element", "elemento", "esc"],
                    category: .view, defaultShortcut: "escape", action: .run { active()?.stopPicking() }, unavailableReason: needsPicking),
        ]
    }
}
