import AppKit
import CommandPalette
import Menus
import Search
import Projects
import Strings
import Tabs
import Themes

/// The palette in the app's colors and its prefixes (docs/spec/
/// command-palette.md): "/" files, "#" text, "@" the tabs and projects.
extension WindowSession {
    /// The ways to open things, first in ⌘K and in the "+" menu next to
    /// the tabs (owner, 2026-10-19).
    /// The right click on a tab (plan 15, phase D).
    static let tabActions = [
        PalettePin(id: "tab.rename", title: T("Rename Tab", "Renomear aba"), icon: .pencilSimple),
        PalettePin(id: "tab.set-color", title: T("Tab Color…", "Cor da aba…"), icon: .palette),
        PalettePin(id: "pane.close", title: T("Close Pane", "Fechar painel"), icon: .x),
    ]

    /// ⌘K's "Open": one way to open each thing, the agent and the task among them; beside, below,
    /// in a new tab and a new window are found by their names (the owner, 2026-11-18: seven ways to
    /// open before anything useful, and none for an agent).
    static let openers = [
        PalettePin(id: "tab.new", title: T("Terminal", "Terminal"), icon: .terminalWindow),
        PalettePin(id: "agents.open-account", title: T("Agent…", "Agente…"), icon: .sparkle),
        PalettePin(id: "worktrees.new-task", title: T("New Task…", "Nova tarefa…"), icon: .gitBranch),
        PalettePin(id: "search.files", title: T("File…", "Arquivo…"), icon: .file),
        PalettePin(id: "preview.open", title: T("Web Preview", "Preview web"), icon: .globe),
    ]
    /// The "+" next to the tabs: a terminal, an agent, a task or a race, then a file or a preview in
    /// a new tab. A new window is not the tabs' (⇧⌘N, the menu).
    static let newOpeners = [
        PalettePin(id: "tab.new", title: T("Terminal", "Terminal"), icon: .terminalWindow),
        PalettePin(id: "agents.open-account", title: T("Agent…", "Agente…"), icon: .sparkle),
        PalettePin(id: "worktrees.new-task", title: T("Task…", "Tarefa…"), icon: .gitBranch),
        PalettePin(id: "worktrees.new-race", title: T("Race…", "Corrida…"), icon: .flag),
        PalettePin(id: "search.files", title: T("File…", "Arquivo…"), icon: .file),
        PalettePin(id: "preview.open-in-tab", title: T("Web Preview", "Preview web"), icon: .globe),
    ]
    /// The pane header's "+": what opens beside the pane, nothing else (its maximize and close are
    /// the header's own buttons; the menu mixed opening with closing, the owner, 2026-11-18).
    static let besideOpeners = [
        PalettePin(id: "pane.split-right", title: T("Terminal on the Right", "Terminal ao lado"), icon: .squareSplitHorizontal),
        PalettePin(id: "pane.split-down", title: T("Terminal Below", "Terminal abaixo"), icon: .squareSplitVertical),
        PalettePin(id: "preview.open", title: T("Web Preview on the Right", "Preview web ao lado"), icon: .globe),
    ]

    /// The tabs' "+": what starts something (a terminal, an agent, a task, a race), a line, then what
    /// opens one (a file, a preview).
    func newTabMenu() -> [MenuEntry] {
        guard let menu else { return [] }
        let starts = Array(Self.newOpeners.prefix(4)), opens = Array(Self.newOpeners.dropFirst(4))
        return MenuEntry.tidy(menu.popup(starts) + [.separator] + menu.popup(opens))
    }

    /// The pane header's menu: what opens beside it.
    func paneMenu() -> [MenuEntry] {
        guard let menu else { return [] }
        return menu.popup(Self.besideOpeners)
    }

    func connectPalette(_ palette: CommandPaletteController) {
        palette.pins = Self.openers
        ThemeStore.shared.observe { [weak palette] theme in
            let ui = theme.interface
            palette?.style = PaletteStyle(
                background: ui.panel.nsColor, border: ui.panelBorder.nsColor, text: ui.text.nsColor,
                secondaryText: ui.secondaryText.nsColor, selection: ui.tabActive.nsColor, accent: ui.accent.nsColor,
                keycap: ui.field.nsColor)
        }
        if let search {
            palette.addPrefix("/", label: T("files", "arquivos"), source: search.files)
            palette.addPrefix("#", label: T("text", "texto"), source: search.content)
        }
        var places: [(String, PaletteSource)] = [(T("Tabs", "Abas"), TabCommands.source { [weak self] in self?.tabs })]
        if let projects { places.append((T("Projects", "Projetos"), ProjectsCommands.source(projects))) }
        palette.addPrefix("@", label: T("tabs and projects", "abas e projetos"), source: MergedSource(
            placeholder: T("Go to a tab or project", "Ir para a aba ou o projeto"),
            emptyText: T("No tabs or projects", "Nenhuma aba ou projeto"), icon: .stack, parts: places))
    }
}
