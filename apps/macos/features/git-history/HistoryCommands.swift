import AppKit
import CommandPalette

/// The history's commands (ADR 0005). The tab's menu and checkbox run
/// these ids; `open` and `repository` come from the app, which knows the
/// Git panel's repository and the tabs.
public enum HistoryCommands {
    @MainActor
    public static func all(open: @escaping @MainActor () -> Void,
                           repository: @escaping @MainActor () -> String?,
                           active: @escaping @MainActor () -> HistoryDocument?) -> [Command] {
        func needsTab() -> String? { active() == nil ? "Nenhum histórico aberto" : nil }
        func needsCommit() -> String? { active()?.hasSelection == true ? nil : "Nenhum commit selecionado" }
        return [
            Command(id: "git.history", title: "Abrir o histórico do git", keywords: ["log", "grafo", "graph", "commits"],
                    category: .view, defaultShortcut: "cmd+shift+h", action: .run { open() },
                    unavailableReason: { repository() == nil ? "Nenhum repositório git aberto" : nil }),
            Command(id: "history.copy-sha", title: "Copiar o sha do commit", keywords: ["sha", "hash", "copiar"],
                    category: .edit, action: .run { active()?.copySha() }, unavailableReason: needsCommit),
            Command(id: "history.open-remote", title: "Abrir o commit no remoto", keywords: ["github", "gitlab", "bitbucket", "navegador"],
                    category: .view, action: .run { active()?.openRemote() }, unavailableReason: needsCommit),
            Command(id: "history.search", title: "Buscar no histórico", keywords: ["filtrar", "commit", "autor"],
                    category: .view, action: .run { active()?.focusSearch() }, unavailableReason: needsTab),
            Command(id: "history.current-branch", title: "Histórico só da branch atual (ligar/desligar)", keywords: ["branch", "filtro", "HEAD"],
                    category: .view, action: .run { active()?.toggleCurrentOnly() }, unavailableReason: needsTab),
            Command(id: "history.refresh", title: "Atualizar o histórico", keywords: ["recarregar", "log"],
                    category: .view, action: .run { active()?.reload() }, unavailableReason: needsTab),
        ]
    }
}
