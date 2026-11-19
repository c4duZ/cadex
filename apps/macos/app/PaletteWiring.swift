import Agents
import AppKit
import Icons
import CommandPalette
import Menus
import Search
import Projects
import Strings
import Tabs
import Themes
import UILooks

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
    /// The "+" next to the tabs: a terminal, an agent (also without memory, plan 35 I), a task or a
    /// race, then a file or a preview in a new tab. A new window is not the tabs' (⇧⌘N, the menu).
    static let newOpeners = [
        PalettePin(id: "tab.new", title: T("Terminal", "Terminal"), icon: .terminalWindow),
        PalettePin(id: "agents.open-account", title: T("Agent…", "Agente…"), icon: .sparkle),
        PalettePin(id: "memory.new-session-without", title: T("Session without Memory", "Sessão sem memória"), icon: .sparkle),
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

    /// The tabs' "+", as the approved proposal draws it: NEW (a terminal, Claude in the account in
    /// use with its logo and usage, opening the accounts' list; a task, a race), then OPEN (a file,
    /// a preview).
    func newTabMenu() -> [MenuEntry] {
        guard let menu else { return [] }
        let pins = Self.newOpeners
        var new = menu.popup(pins.filter { $0.id == "tab.new" })
        if let agent = claudeMenuEntry() { new.append(agent) }
        // Plan 35 I: a session that records nothing and gets no briefing.
        new += menu.popup(pins.filter { $0.id == "memory.new-session-without" })
        new += menu.popup(pins.filter { ["worktrees.new-task", "worktrees.new-race"].contains($0.id) })
        let open = menu.popup(pins.filter { ["search.files", "preview.open-in-tab"].contains($0.id) })
        return MenuEntry.tidy([.caption(T("New", "Novo"))] + new + [.separator, .caption(T("Open", "Abrir"))] + open)
    }

    /// "Claude in bhband  22% ›": the account new sessions use, its usage; the caret's list is
    /// agents.open-account (every account).
    private func claudeMenuEntry() -> MenuEntry? {
        guard let dir = shownAccountDir(), let account = AgentsController.shared.everyAccount().first(where: { $0.dir == dir }) else { return nil }
        var entry = MenuEntry(T("Claude in \(account.name)", "Claude em \(account.name)")) { [weak self] in
            _ = self?.commands.run("agents.open-account")
        }
        entry.image = ProviderLogo.claude.image(size: 16)
        entry.imageTint = ProviderLogo.claude.brandColor
        entry.detail = AgentSwitch.used(AgentUsage.current(of: account)).map { "\($0)%" }
        entry.opensList = true
        return entry
    }

    /// ⌘K's "Now" (the approved proposal): each agent waiting for you, "Answer <where>" with what it
    /// asks, and going on in another account when the focused terminal runs Claude.
    private func nowRows() -> [PaletteItem] {
        var rows = AgentAttention.shared.cards.prefix(3).map { card in
            var item = PaletteItem(id: "now:card:" + card.id, title: T("Answer \(card.project)", "Responder \(card.project)"))
            item.note = card.title.isEmpty ? card.detail : card.title
            item.tile = .kind(.hand, DesignTokens.Color.stateNeeds)
            return item
        }
        if let terminal = tabs?.activeTerminal, claudeAccount(in: terminal) != nil {
            var item = PaletteItem(id: "now:switch", title: T("Go on in another account…", "Continuar em outra conta…"))
            item.tile = .kind(.arrowsLeftRight, DesignTokens.Color.stateWorking)
            rows.append(item)
        }
        return Array(rows)
    }

    private func runNow(_ id: String) {
        if id == "now:switch" { _ = commands.run("agents.switch-account"); return }
        let cardID = String(id.dropFirst("now:card:".count))
        guard let card = AgentAttention.shared.cards.first(where: { $0.id == cardID }) else { return }
        app.goToAgent(key: card.key, pid: card.pid)
    }

    /// The pane header's menu: what opens beside it.
    func paneMenu() -> [MenuEntry] {
        guard let menu else { return [] }
        return menu.popup(Self.besideOpeners)
    }

    func connectPalette(_ palette: CommandPaletteController) {
        palette.pins = Self.openers
        palette.setNow({ [weak self] in self?.nowRows() ?? [] }, run: { [weak self] id in self?.runNow(id) })
        ThemeStore.shared.observe { [weak palette] theme in
            let ui = theme.interface
            // The chosen row blue-gray, as the approved proposal (#202833 on the dark theme).
            palette?.style = PaletteStyle(
                background: ui.panel.nsColor, border: ui.panelBorder.nsColor, text: ui.text.nsColor,
                secondaryText: ui.secondaryText.nsColor,
                selection: ui.panel.nsColor.blended(withFraction: 0.14, of: ui.accent.nsColor) ?? ui.tabActive.nsColor,
                accent: ui.accent.nsColor, keycap: ui.field.nsColor)
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
