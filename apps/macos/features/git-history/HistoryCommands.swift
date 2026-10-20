import AppKit
import CommandPalette
import Strings

/// The history's commands (ADR 0005). The tab's menu and checkbox run
/// these ids; `open` and `repository` come from the app, which knows the
/// Git panel's repository and the tabs.
public enum HistoryCommands {
    @MainActor
    /// open: the history beside (true), in a new tab (false) or where the
    /// setting says (nil).
    public static func all(open: @escaping @MainActor (Bool?) -> Void,
                           repository: @escaping @MainActor () -> String?,
                           active: @escaping @MainActor () -> HistoryDocument?) -> [Command] {
        func needsRepository() -> String? { repository() == nil ? T("No git repository open", "Nenhum repositório git aberto") : nil }
        func needsTab() -> String? { active() == nil ? T("No history open", "Nenhum histórico aberto") : nil }
        func needsCommit() -> String? { active()?.hasSelection == true ? nil : T("No commit selected", "Nenhum commit selecionado") }
        return [
            Command(id: "git.history", title: T("Open Git History", "Abrir o histórico do git"), keywords: ["log", "grafo", "graph", "commits"],
                    category: .view, defaultShortcut: "cmd+shift+h", action: .run { open(nil) },
                    unavailableReason: needsRepository),
            Command(id: "git.history-in-tab", title: T("Open Git History in New Tab", "Abrir o histórico do git em nova aba"),
                    keywords: ["log", "grafo", "graph", "commits", "aba"], category: .view, action: .run { open(false) },
                    unavailableReason: needsRepository),
            Command(id: "history.copy-sha", title: T("Copy Commit SHA", "Copiar o sha do commit"), keywords: ["sha", "hash", "copy", "copiar"],
                    category: .edit, action: .run { active()?.copySha() }, unavailableReason: needsCommit),
            Command(id: "history.open-remote", title: T("Open Commit on Remote", "Abrir o commit no remoto"), keywords: ["github", "gitlab", "bitbucket", "browser", "navegador"],
                    category: .view, action: .run { active()?.openRemote() }, unavailableReason: needsCommit),
            Command(id: "history.search", title: T("Search History", "Buscar no histórico"), keywords: ["filter", "author", "filtrar", "commit", "autor"],
                    category: .view, action: .run { active()?.focusSearch() }, unavailableReason: needsTab),
            Command(id: "history.current-branch", title: T("Toggle Current Branch Only in History", "Histórico só da branch atual (ligar/desligar)"), keywords: ["branch", "filter", "filtro", "HEAD"],
                    category: .view, action: .run { active()?.toggleCurrentOnly() }, unavailableReason: needsTab),
            Command(id: "history.refresh", title: T("Refresh History", "Atualizar o histórico"), keywords: ["reload", "recarregar", "log"],
                    category: .view, action: .run { active()?.reload() }, unavailableReason: needsTab),
        ]
    }
}
