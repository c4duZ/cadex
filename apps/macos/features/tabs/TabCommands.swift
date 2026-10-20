import CommandPalette
import Strings

/// The commands of the tabs feature (ADR 0005), acting on a window's tabs.
public enum TabCommands {
    private static let noTabs = T("No tab open", "Nenhuma aba aberta")

    @MainActor
    public static func all(_ tabs: @escaping @MainActor () -> TabsController?) -> [Command] {
        func needsTabs() -> String? { (tabs()?.count ?? 0) > 0 ? nil : noTabs }
        func needsTwo() -> String? { (tabs()?.count ?? 0) > 1 ? nil : T("Only one tab open", "Só uma aba aberta") }
        var list: [Command] = [
            Command(id: "tab.new", title: T("New Tab", "Nova aba"), keywords: ["new tab", "terminal", "abrir", "open"], category: .tabs,
                    defaultShortcut: "cmd+t", action: .run { tabs()?.newTab() }),
            Command(id: "pane.close", title: T("Close Pane", "Fechar painel"), keywords: ["close", "fechar aba", "close tab"], category: .panes,
                    defaultShortcut: "cmd+w", action: .run { tabs()?.closeFocusedPane() }, unavailableReason: needsTabs),
            Command(id: "tab.rename", title: T("Rename Tab", "Renomear aba"), keywords: ["rename", "nome"], category: .tabs,
                    action: .run { tabs()?.renameActive() }, unavailableReason: needsTabs),
            Command(id: "tab.previous-used", title: T("Back to Previous Tab", "Voltar para a aba anterior"), keywords: ["recent", "alternar", "switch"],
                    category: .tabs, defaultShortcut: "ctrl+tab", action: .run { tabs()?.selectPreviouslyUsed() },
                    unavailableReason: needsTwo),
            Command(id: "tab.least-recently-used", title: T("Go to Least Recently Used Tab", "Ir para a aba usada há mais tempo"), keywords: ["recent", "alternar"],
                    category: .tabs, defaultShortcut: "ctrl+shift+tab", action: .run { tabs()?.selectLeastRecentlyUsed() },
                    unavailableReason: needsTwo),
        ]
        func needsSplit() -> String? { (tabs()?.activePaneCount ?? 0) > 1 ? nil : T("Only one pane in this tab", "Só um painel nesta aba") }
        list += [
            Command(id: "pane.split-right", title: T("Split Right", "Dividir à direita"), keywords: ["split", "painel", "lado"],
                    category: .panes, defaultShortcut: "cmd+d", action: .run { tabs()?.split(.horizontal) },
                    unavailableReason: needsTabs),
            Command(id: "pane.split-down", title: T("Split Down", "Dividir para baixo"), keywords: ["split", "painel", "embaixo"],
                    category: .panes, defaultShortcut: "cmd+shift+d", action: .run { tabs()?.split(.vertical) },
                    unavailableReason: needsTabs),
            Command(id: "pane.next", title: T("Next Pane", "Próximo painel"), keywords: ["pane", "foco"], category: .panes,
                    defaultShortcut: "cmd+]", action: .run { tabs()?.focusPane(step: 1) }, unavailableReason: needsSplit),
            Command(id: "pane.previous", title: T("Previous Pane", "Painel anterior"), keywords: ["pane", "foco"], category: .panes,
                    defaultShortcut: "cmd+[", action: .run { tabs()?.focusPane(step: -1) }, unavailableReason: needsSplit),
        ]
        let directions: [(String, String, String, PaneTree.Direction)] = [
            ("left", T("Go to Left Pane", "Ir para o painel à esquerda"), "left", .left),
            ("right", T("Go to Right Pane", "Ir para o painel à direita"), "right", .right),
            ("up", T("Go to Pane Above", "Ir para o painel acima"), "up", .up),
            ("down", T("Go to Pane Below", "Ir para o painel abaixo"), "down", .down),
        ]
        for (id, title, key, direction) in directions {
            list.append(Command(
                id: "pane.focus-\(id)", title: title, keywords: ["pane", "foco", "focus"], category: .panes,
                defaultShortcut: "cmd+opt+\(key)", action: .run { tabs()?.focusPane(direction) },
                unavailableReason: needsSplit))
        }
        for n in 1...9 {
            list.append(Command(
                id: "tab.select-\(n)", title: T("Go to Tab \(n)", "Ir para a aba \(n)"), keywords: ["tab \(n)"], category: .tabs,
                defaultShortcut: "cmd+\(n)", action: .run { tabs()?.select(position: n) },
                unavailableReason: { (tabs()?.count ?? 0) >= n ? nil : T("There is no tab \(n)", "Não há aba \(n)") }))
        }
        return list
    }
}
