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
        return [
            Command(id: "preview.open", title: T("Open Web Preview", "Abrir preview web"), keywords: ["browser", "navegador", "localhost", "site"],
                    category: .view, action: .run { open("", nil) }),
            Command(id: "preview.open-in-tab", title: T("Open Web Preview in New Tab", "Abrir preview web em nova aba"),
                    keywords: ["browser", "navegador", "localhost", "site", "aba"], category: .view, action: .run { open("", false) }),
            Command(id: "preview.reload", title: T("Reload Preview", "Recarregar o preview"), keywords: ["reload", "refresh", "atualizar"], category: .view,
                    defaultShortcut: "cmd+r", action: .run { active()?.reload() }, unavailableReason: needsPreview),
            Command(id: "preview.back", title: T("Go Back in Preview", "Voltar no preview"), keywords: ["back", "previous", "anterior"], category: .view,
                    action: .run { active()?.goBack() }, unavailableReason: needsPreview),
            Command(id: "preview.forward", title: T("Go Forward in Preview", "Avançar no preview"), keywords: ["forward", "next", "próxima"], category: .view,
                    action: .run { active()?.goForward() }, unavailableReason: needsPreview),
        ]
    }
}
