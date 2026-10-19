import CommandPalette

/// The commands of the tabs feature (ADR 0005), acting on a window's tabs.
public enum TabCommands {
    private static let noTabs = "Nenhuma aba aberta"

    @MainActor
    public static func all(_ tabs: @escaping @MainActor () -> TabsController?) -> [Command] {
        func needsTabs() -> String? { (tabs()?.count ?? 0) > 0 ? nil : noTabs }
        func needsTwo() -> String? { (tabs()?.count ?? 0) > 1 ? nil : "Só uma aba aberta" }
        var list: [Command] = [
            Command(id: "tab.new", title: "Nova aba", keywords: ["new tab", "terminal", "abrir"], category: .tabs,
                    defaultShortcut: "cmd+t", action: .run { tabs()?.newTab() }),
            Command(id: "pane.close", title: "Fechar painel", keywords: ["close", "fechar aba"], category: .tabs,
                    defaultShortcut: "cmd+w", action: .run { tabs()?.closeFocusedPane() }, unavailableReason: needsTabs),
            Command(id: "tab.rename", title: "Renomear aba", keywords: ["rename", "nome"], category: .tabs,
                    action: .run { tabs()?.renameActive() }, unavailableReason: needsTabs),
            Command(id: "tab.previous-used", title: "Voltar para a aba anterior", keywords: ["recent", "alternar"],
                    category: .tabs, defaultShortcut: "ctrl+tab", action: .run { tabs()?.selectPreviouslyUsed() },
                    unavailableReason: needsTwo),
            Command(id: "tab.least-recently-used", title: "Ir para a aba usada há mais tempo", keywords: ["recent", "alternar"],
                    category: .tabs, defaultShortcut: "ctrl+shift+tab", action: .run { tabs()?.selectLeastRecentlyUsed() },
                    unavailableReason: needsTwo),
        ]
        for n in 1...9 {
            list.append(Command(
                id: "tab.select-\(n)", title: "Ir para a aba \(n)", keywords: ["tab \(n)"], category: .tabs,
                defaultShortcut: "cmd+\(n)", action: .run { tabs()?.select(position: n) },
                unavailableReason: { (tabs()?.count ?? 0) >= n ? nil : "Não há aba \(n)" }))
        }
        return list
    }
}
