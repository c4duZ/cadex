import AppKit
import Strings

/// The settings' sections' rows (plan 32 B): what was one long General page, each module in its
/// own section of the window's list (the owner, 2026-11-18: "as configurações não estão
/// aparecendo… é cheio de módulo novo"). Each function gives a section's rows, also searched.
@MainActor
enum SectionRows {
    static func general(_ store: SettingsStore, askRelaunch: @escaping (String?) -> Void) -> [NSView] {
        let g = store.settings.general
        return [
            SettingsPage.section(T("Language", "Idioma")),
            SettingsPage.row(T("Language", "Idioma"),
                             T("Cadex reopens in the new language, with your tabs and projects.",
                               "O Cadex reabre no idioma novo, com as suas abas e projetos."),
                             control: SettingsPage.popup([("English", "en"), ("Português", "pt")], selected: g.language) { value in
                                 guard value != store.settings.general.language else { return }
                                 store.update { $0.general.language = value }
                                 askRelaunch(value)
                             }),
        ] + InterfaceRows.make(store, askRelaunch: askRelaunch) + KeepAwakeRows.make(store)
    }

    static func files(_ store: SettingsStore) -> [NSView] {
        let g = store.settings.general
        let e = store.settings.explorer
        return [
            SettingsPage.section(T("Files", "Arquivos")),
            SettingsPage.row(T("Open files", "Abrir arquivos"),
                             T("Where a file or a web preview opens: next to the focused pane, or in a new tab (a diff opens in the review). “Open beside” and “Open in new tab” choose on the spot.",
                               "Onde abre um arquivo ou um preview web: ao lado do painel com foco, ou numa aba nova (um diff abre na revisão). “Abrir ao lado” e “Abrir em nova aba” escolhem na hora."),
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
            SettingsPage.section(T("File tree", "Árvore de arquivos")),
            SettingsPage.row(T("Follow the terminal", "Seguir o terminal"),
                             T("When you cd in the focused terminal, the tree moves to that project: the top of its git repository, or the folder itself.",
                               "Quando você dá cd no terminal com foco, a árvore vai para aquele projeto: a raiz do repositório git, ou a própria pasta."),
                             control: SettingsPage.toggle(e.followTerminal) { on in store.update { $0.explorer.followTerminal = on } }),
            SettingsPage.row(T("Show hidden files", "Mostrar arquivos ocultos"),
                             T("Files and folders whose names start with a dot, dimmed. ⇧⌘. switches too.",
                               "Arquivos e pastas cujo nome começa com ponto, apagados. O ⇧⌘. também troca."),
                             control: SettingsPage.toggle(e.showHidden) { on in store.update { $0.explorer.showHidden = on } }),
            SettingsPage.section(T("Web preview", "Preview web")),
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
        ]
    }

    static func git(_ store: SettingsStore) -> [NSView] {
        [
            SettingsPage.section(T("Tasks", "Tarefas")),
            SettingsPage.row(T("Folder of the tasks", "Pasta das tarefas"),
                             T("Where New Task makes each repository's worktrees, in a folder with the repository's name. Empty: beside the repository, in <repo>.worktrees. The setup hooks are edited per repository on the Tasks page.",
                               "Onde o Nova tarefa cria as worktrees de cada repositório, numa pasta com o nome dele. Vazio: ao lado do repositório, em <repo>.worktrees. Os hooks de preparo se editam por repositório na página Tarefas."),
                             control: SettingsPage.text(store.settings.worktrees.root, placeholder: T("Beside each repository", "Ao lado de cada repositório")) { value in
                                 store.update { $0.worktrees.root = value.trimmingCharacters(in: .whitespaces) }
                             }),
            SettingsPage.section(T("Review", "Revisão")),
            SettingsPage.row(T("Mark the lines agents write", "Marcar as linhas que os agentes escrevem"),
                             T("In a task's review, a thin bar marks the lines an agent opened by Cadex wrote. Only line ranges are kept, in Cadex, never in git. Off, sessions get no hook for it.",
                               "Na revisão de uma tarefa, uma barra fina marca as linhas que um agente aberto pelo Cadex escreveu. Só os intervalos de linhas ficam guardados, no Cadex, nunca no git. Desligado, as sessões não ganham o hook disso."),
                             control: SettingsPage.toggle(store.settings.review.authorship) { on in store.update { $0.review.authorship = on } }),
        ]
    }

    static func agents(_ store: SettingsStore) -> [NSView] {
        [
            SettingsPage.section(T("Agents", "Agentes")),
            SettingsPage.row(T("Read agent sessions", "Ler as sessões dos agentes"),
                             T("The tree, the bell and the project page show the Claude Code sessions of every account on this Mac. Cadex only reads their files, never runs an agent. Off, nothing of theirs is opened.",
                               "A árvore, o sino e a página do projeto mostram as sessões do Claude Code de todas as contas deste Mac. O Cadex só lê os arquivos delas, nunca roda um agente. Desligado, nada delas é aberto."),
                             control: SettingsPage.toggle(store.settings.agents.sessions) { on in store.update { $0.agents.sessions = on } }),
            SettingsPage.row(T("Read plan usage", "Ler o uso dos planos"),
                             T("Agents › Accounts and the status bar show how much of each account's plan is used, as Claude Code tells it to the sessions Cadex opens. Cadex never reads a login or token and asks no service.",
                               "Agents › Contas e a barra de status mostram quanto do plano de cada conta foi usado, como o Claude Code conta às sessões que o Cadex abre. O Cadex nunca lê login nem token e não pergunta a serviço nenhum."),
                             control: SettingsPage.toggle(store.settings.agents.accounts) { on in store.update { $0.agents.accounts = on } }),
            SettingsPage.row(T("Session hooks", "Hooks das sessões"),
                             T("Sessions Cadex opens tell it, through Claude Code's hooks, which conversation they run (after /clear and --resume). They never make the agent wait. Off, no hooks are added.",
                               "As sessões que o Cadex abre contam a ele, pelos hooks do Claude Code, qual conversa estão rodando (depois de /clear e --resume). Nunca fazem o agente esperar. Desligado, nenhum hook é posto."),
                             control: SettingsPage.toggle(store.settings.agents.stateHooks) { on in store.update { $0.agents.stateHooks = on } }),
            SettingsPage.row(T("Hibernate quiet agents after", "Hibernar agentes parados depois de"),
                             T("An agent opened by Cadex that finished, that you are not looking at, ends after this many minutes to free memory, and comes back with its conversation when you open its terminal again. 0 turns it off.",
                               "Um agente aberto pelo Cadex que terminou, e que você não está olhando, encerra depois desses minutos para liberar memória, e volta com a conversa quando você abre o terminal dele de novo. 0 desliga."),
                             control: SettingsPage.number(Double(store.settings.agents.hibernateAfterMinutes), range: 0...240, step: 5, format: "%.0f min") { value in
                                 store.update { $0.agents.hibernateAfterMinutes = Int(value) }
                             }),
            SettingsPage.row(T("Index conversation history", "Indexar o histórico de conversas"),
                             T("Agents › History searches every conversation of every account. Cadex reads the conversation files only while the page shows, never a tool's result, and keeps the index on this Mac. Off, nothing is indexed or watched.",
                               "Agents › Histórico busca todas as conversas de todas as contas. O Cadex lê os arquivos das conversas só com a página aberta, nunca o resultado de uma ferramenta, e guarda o índice neste Mac. Desligado, nada é indexado nem vigiado."),
                             control: SettingsPage.toggle(store.settings.agents.history) { on in store.update { $0.agents.history = on } }),
            SettingsPage.section(T("What agents can use", "O que os agentes podem usar")),
            SettingsPage.row(T("Agents can use Cadex", "Os agentes podem usar o Cadex"),
                             T("Sessions Cadex opens get the cadex command and its MCP tools: they can open files, diffs and pages beside you, notify you and mark their task's progress. Nothing can close, delete or change a setting. Off, they get none of it.",
                               "As sessões que o Cadex abre ganham o comando cadex e as ferramentas MCP dele: abrem arquivos, diffs e páginas ao seu lado, avisam você e marcam o andamento da tarefa. Nada fecha, apaga ou muda configuração. Desligado, não ganham nada disso."),
                             control: SettingsPage.toggle(store.settings.agentTools.enabled) { on in store.update { $0.agentTools.enabled = on } }),
            SettingsPage.row(T("Agents can use the preview", "Os agentes podem usar o preview"),
                             T("An agent drives a preview tab beside you, as a browser: it goes to a page, reads it, clicks, fills and takes pictures; a band shows it and Esc stops it.",
                               "Um agente dirige uma aba de preview ao seu lado, como um navegador: vai a uma página, lê, clica, preenche e tira prints; uma faixa mostra e o Esc para."),
                             control: SettingsPage.toggle(store.settings.agentTools.browser) { on in store.update { $0.agentTools.browser = on } }),
            // Its own section (the owner, 2026-11-20: "porque isso não está em settings?"; it was one
            // row among the others, with no word "computer use" in its title).
            SettingsPage.section(T("Computer use", "Computer use")),
            SettingsPage.row(T("Agents can use other apps", "Os agentes podem usar outros apps"),
                             T("Computer use: an agent reads and operates other apps of this Mac by accessibility, asking you app by app the first time. Never password fields, System Settings, Keychain Access, Terminal or Cadex itself. Turning it on asks macOS for Accessibility and Screen Recording.",
                               "Computer use: um agente lê e opera outros apps deste Mac pela acessibilidade, pedindo a você app por app na primeira vez. Nunca campos de senha, Ajustes do Sistema, Acesso às Chaves, Terminal nem o próprio Cadex. Ligar pede ao macOS Acessibilidade e Gravação de Tela."),
                             control: SettingsPage.toggle(store.settings.computerUse.enabled) { on in store.update { $0.computerUse.enabled = on } }),
        ] + computerUseRows(store)
    }

    /// The apps already allowed (a yes is kept until forgotten) and macOS's two permissions.
    static func computerUseRows(_ store: SettingsStore) -> [NSView] {
        let allowed = store.settings.computerUse.allowedApps
        let names = allowed.map { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { FileManager.default.displayName(atPath: $0.path) } ?? id
        }
        let forget = SettingsPage.button(T("Forget All", "Esquecer todos")) { store.update { $0.computerUse.allowedApps = [] } }
        forget.isEnabled = !allowed.isEmpty
        let open = SettingsPage.button(T("Open Privacy & Security", "Abrir Privacidade e Segurança")) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") { NSWorkspace.shared.open(url) }
        }
        return [
            SettingsPage.row(T("Apps allowed", "Apps permitidos"),
                             names.isEmpty ? T("None yet: the first time an agent wants an app, Cadex asks you.", "Nenhum ainda: na primeira vez que um agente quer um app, o Cadex pergunta a você.")
                                 : names.sorted().joined(separator: ", "),
                             control: forget),
            SettingsPage.row(T("macOS permissions", "Permissões do macOS"),
                             T("Cadex needs Accessibility (to read and operate apps) and Screen Recording (for a picture of one window).",
                               "O Cadex precisa de Acessibilidade (para ler e operar os apps) e de Gravação de Tela (para o print de uma janela)."),
                             control: open),
        ]
    }

    static func notifications(_ store: SettingsStore) -> [NSView] {
        [
            SettingsPage.section(T("Needs you", "Precisa de você")),
            SettingsPage.row(T("What needs you", "O que precisa de você"),
                             T("The bell in the title bar counts the agents' open requests and the ones that finished while you were away; it opens what needs you, with Allow and Deny, and the feed.",
                               "O sino na barra de título conta os pedidos abertos dos agentes e os que terminaram enquanto você não olhava; ele abre o que precisa de você, com Permitir e Negar, e o feed."),
                             control: SettingsPage.toggle(store.settings.agents.attention) { on in store.update { $0.agents.attention = on } }),
            SettingsPage.row(T("Number on the Dock", "Número no Dock"),
                             T("The same count on Cadex's icon in the Dock.", "A mesma contagem no ícone do Cadex no Dock."),
                             control: SettingsPage.toggle(store.settings.agents.dockBadge) { on in store.update { $0.agents.dockBadge = on } }),
            SettingsPage.row(T("Mute this Mac's agents", "Silenciar os agentes deste Mac"),
                             T("No notification from the agents running on this Mac; the bell still counts.",
                               "Nenhuma notificação dos agentes que rodam neste Mac; o sininho continua contando."),
                             control: SettingsPage.toggle(store.settings.agents.mutedMachines.contains("local")) { on in
                                 store.update { s in
                                     s.agents.mutedMachines.removeAll { $0 == "local" }
                                     if on { s.agents.mutedMachines.append("local") }
                                 }
                             }),
            SettingsPage.section(T("Notifications", "Notificações")),
        ] + NotificationRows.make(store)
    }

    static func machines(_ store: SettingsStore) -> [NSView] {
        [
            SettingsPage.section(T("SSH", "SSH")),
            SettingsPage.row(T("Test SSH hosts", "Testar os hosts SSH"),
                             T("While the SSH item shows in the status bar, each host of ~/.ssh/config gets a connection to its port, on open and every 10 minutes. No login, no command.",
                               "Enquanto o item SSH aparece na barra de status, cada host do ~/.ssh/config recebe uma conexão na porta dele, ao abrir e a cada 10 minutos. Sem login, sem comando."),
                             control: SettingsPage.toggle(store.settings.ssh.ping) { on in store.update { $0.ssh.ping = on } }),
            SettingsPage.section(T("Tailnet", "Tailnet")),
            SettingsPage.row(T("Tailnet machines", "Máquinas da tailnet"),
                             T("With Tailscale running, the SSH card lists your tailnet's machines under the hosts. Cadex reads the list from your Tailscale only while the card or ⌘K shows it, and never changes its settings. Off, Cadex does not touch Tailscale at all.",
                               "Com o Tailscale rodando, o cartão do SSH lista as máquinas da sua tailnet abaixo dos hosts. O Cadex lê a lista do seu Tailscale só enquanto o cartão ou o ⌘K a mostram, e nunca muda a configuração dele. Desligado, o Cadex não toca no Tailscale."),
                             control: SettingsPage.toggle(store.settings.machines.tailscale) { on in store.update { $0.machines.tailscale = on } }),
            SettingsPage.row(T("Accept your other devices", "Aceitar seus outros aparelhos"),
                             T("Cadex listens on this Mac's tailnet address only (never on the local network) for your own devices, checked by Tailscale; anyone else's is closed. For the remote Cadex and the phone that come later. Off, nothing listens.",
                               "O Cadex ouve só no endereço deste Mac na tailnet (nunca na rede local), para os seus próprios aparelhos, conferidos pelo Tailscale; o de outra pessoa é fechado. Para o Cadex remoto e o celular, que vêm depois. Desligado, nada ouve."),
                             control: SettingsPage.toggle(store.settings.machines.acceptRemote) { on in store.update { $0.machines.acceptRemote = on } }),
        ]
    }
}
