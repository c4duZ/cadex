import AppKit
import Strings

/// The "General" and "About" pages (docs/spec/settings.md): rows of
/// controls that change settings.json at once, in sections, each saying
/// what it changes (owner, 2026-10-20: the old texts were badly put).
@MainActor
enum GeneralPages {
    /// askRelaunch: the language (or, with nil, the interface's size or
    /// font) changed; it counts when Cadex reopens.
    static func general(_ store: SettingsStore, askRelaunch: @escaping (String?) -> Void) -> NSView {
        let g = store.settings.general
        let e = store.settings.explorer
        return SettingsPage.make(
            title: T("General", "Geral"),
            subtitle: T("Language, where files open, the file tree and keeping the computer awake.",
                        "Idioma, onde os arquivos abrem, a árvore de arquivos e manter o computador acordado."),
            rows: [
                SettingsPage.section(T("Language", "Idioma")),
                SettingsPage.row(T("Language", "Idioma"),
                                 T("Cadex reopens in the new language, with your tabs and spaces.",
                                   "O Cadex reabre no idioma novo, com as suas abas e spaces."),
                                 control: SettingsPage.popup([("English", "en"), ("Português", "pt")], selected: g.language) { value in
                                     guard value != store.settings.general.language else { return }
                                     store.update { $0.general.language = value }
                                     askRelaunch(value)
                                 }),

                SettingsPage.section(T("Files", "Arquivos")),
                SettingsPage.row(T("Open files", "Abrir arquivos"),
                                 T("Where a file, a diff or a web preview opens: next to the focused pane, or in a new tab. “Open beside” and “Open in new tab” choose on the spot.",
                                   "Onde abre um arquivo, um diff ou um preview web: ao lado do painel com foco, ou numa aba nova. “Abrir ao lado” e “Abrir em nova aba” escolhem na hora."),
                                 control: SettingsPage.popup([(T("Beside", "Ao lado"), "beside"), (T("New tab", "Em nova aba"), "tab")],
                                                             selected: g.openFiles) { value in store.update { $0.general.openFiles = value } }),
                SettingsPage.row(T("Side of a file opened beside", "Lado do arquivo aberto ao lado"),
                                 T("A file opened beside takes half the tab, on this side; the terminals share the other half and get it back when it closes.",
                                   "Um arquivo aberto ao lado fica com metade da aba, deste lado; os terminais dividem a outra metade e a recebem de volta quando ele fecha."),
                                 control: SettingsPage.popup([(T("Right", "Direita"), "right"), (T("Left", "Esquerda"), "left")],
                                                             selected: store.settings.tabs.documentSide) { value in
                                     store.update { $0.tabs.documentSide = value }
                                 }),
                SettingsPage.row(T("Open Markdown as", "Abrir Markdown como"),
                                 T("How a note opens. The button in the tab's corner switches at any time.",
                                   "Como uma nota abre. O botão no canto da aba troca a qualquer hora."),
                                 control: SettingsPage.popup([(T("Source", "Código"), "source"), (T("Rendered", "Renderizado"), "rendered")],
                                                             selected: store.settings.markdown.openAs) { value in
                                     store.update { $0.markdown.openAs = value }
                                 }),
                SettingsPage.row(T("Picked element goes to", "Elemento escolhido vai para"),
                                 T("In the web preview, ⌘⇧C picks an element of the page. It is pasted into the agent running in a terminal, without Enter, or copied. ⌥+click copies either way.",
                                   "No preview web, ⌘⇧C escolhe um elemento da página. Ele é colado no agente que roda num terminal, sem Enter, ou copiado. ⌥+clique copia de qualquer jeito."),
                                 control: SettingsPage.popup([(T("The agent's terminal", "O terminal do agente"), "terminal"),
                                                              (T("The clipboard", "A área de transferência"), "clipboard")],
                                                             selected: store.settings.preview.pickTarget) { value in
                                     store.update { $0.preview.pickTarget = value }
                                 }),
                SettingsPage.row(T("Picture of the picked element", "Print do elemento escolhido"),
                                 T("A picture of the element goes along, as the path of a PNG the agent can open.",
                                   "Um print do elemento vai junto, como o caminho de um PNG que o agente consegue abrir."),
                                 control: SettingsPage.toggle(store.settings.preview.pickScreenshot) { on in
                                     store.update { $0.preview.pickScreenshot = on }
                                 }),

                SettingsPage.section(T("Agents", "Agentes")),
                SettingsPage.row(T("Read agent sessions", "Ler as sessões dos agentes"),
                                 T("The Agents page lists the Claude Code sessions of every account on this Mac. Cadex only reads their files, never runs an agent. Off, nothing of theirs is opened.",
                                   "A página Agents lista as sessões do Claude Code de todas as contas deste Mac. O Cadex só lê os arquivos delas, nunca roda um agente. Desligado, nada delas é aberto."),
                                 control: SettingsPage.toggle(store.settings.agents.sessions) { on in store.update { $0.agents.sessions = on } }),
                SettingsPage.row(T("Notify when an agent asks permission", "Avisar quando um agente pede permissão"),
                                 T("A notification from macOS; a click goes to its terminal. Not while you look at that terminal.",
                                   "Uma notificação do macOS; o clique leva ao terminal dele. Não enquanto você olha aquele terminal."),
                                 control: SettingsPage.toggle(store.settings.agents.notifyPermission) { on in store.update { $0.agents.notifyPermission = on } }),
                SettingsPage.row(T("Notify when an agent asks a question", "Avisar quando um agente faz uma pergunta"), nil,
                                 control: SettingsPage.toggle(store.settings.agents.notifyQuestion) { on in store.update { $0.agents.notifyQuestion = on } }),
                SettingsPage.row(T("Notify when an agent finishes", "Avisar quando um agente termina"), nil,
                                 control: SettingsPage.toggle(store.settings.agents.notifyFinished) { on in store.update { $0.agents.notifyFinished = on } }),

                SettingsPage.section(T("File tree", "Árvore de arquivos")),
                SettingsPage.row(T("Follow the terminal", "Seguir o terminal"),
                                 T("When you cd in the focused terminal, the tree moves to that project: the top of its git repository, or the folder itself.",
                                   "Quando você dá cd no terminal com foco, a árvore vai para aquele projeto: a raiz do repositório git, ou a própria pasta."),
                                 control: SettingsPage.toggle(e.followTerminal) { on in store.update { $0.explorer.followTerminal = on } }),
                SettingsPage.row(T("Show hidden files", "Mostrar arquivos ocultos"),
                                 T("Files and folders whose names start with a dot, dimmed. ⇧⌘. switches too.",
                                   "Arquivos e pastas cujo nome começa com ponto, apagados. O ⇧⌘. também troca."),
                                 control: SettingsPage.toggle(e.showHidden) { on in store.update { $0.explorer.showHidden = on } }),
            ] + InterfaceRows.make(store, askRelaunch: askRelaunch) + KeepAwakeRows.make(store))
    }

    static func about() -> NSView {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? T("development", "desenvolvimento")
        let credits = NSTextField(wrappingLabelWithString: T(
            "A terminal-centered development workspace, native, with its own code under the MIT license. The terminal model is libghostty-vt; the icons are Phosphor; the themes come from the official palettes of open themes, tweakcn and the base16 schemes of tinted-theming. Full credits in the NOTICE file.",
            "Workspace de desenvolvimento centrado no terminal, nativo, com código próprio sob a licença MIT. O modelo do terminal é a libghostty-vt; os ícones são Phosphor; os temas vêm das paletas oficiais de temas abertos, do tweakcn e dos esquemas base16 do tinted-theming. Créditos completos no arquivo NOTICE."))
        credits.textColor = SettingsColors.secondaryText
        return SettingsPage.make(title: "Cadex", subtitle: T("Version", "Versão") + " \(version)", rows: [credits])
    }
}
