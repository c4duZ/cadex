import AppKit
import Strings

/// The Phone section (the owner, 2026-11-20: "colocar nas configurações o negócio de celular e
/// explicar como usa o Claude pelo Tailscale"; docs/guides/phone.md): what must be on, the `cadex`
/// command for the SSH session, macOS's Remote Login, and how it is used from the phone.
@MainActor
enum PhoneRows {
    static func make(_ store: SettingsStore) -> [NSView] {
        [
            SettingsPage.note(T("From your phone's terminal app (Termius, Blink), over SSH through your tailnet: join the tabs open in Cadex as they are, open a terminal or Claude in a project (the tab shows on the Mac too), and open in Safari what the agent made. It is the same session: the same Claude, account and memory.",
                                "Pelo app de terminal do celular (Termius, Blink), por SSH pela sua tailnet: entrar nas abas abertas no Cadex como estão, abrir um terminal ou o Claude num projeto (a aba aparece no Mac também) e abrir no Safari o que o agente fez. É a mesma sessão: o mesmo Claude, a conta e a memória.")),
            SettingsPage.section(T("On this Mac, once", "Neste Mac, uma vez")),
            SettingsPage.row(T("Keep terminals when Cadex quits", "Manter os terminais quando o Cadex fecha"),
                             T("Needed: the tabs live in a small process of their own, which the phone joins. Tabs opened after turning it on.",
                               "Necessário: as abas moram num processo pequeno à parte, onde o celular entra. Vale para as abas abertas depois de ligar."),
                             control: SettingsPage.toggle(store.settings.terminal.keepSessions) { on in store.update { $0.terminal.keepSessions = on } }),
            SettingsPage.row(T("Tailnet machines", "Máquinas da tailnet"),
                             T("For cadex share: a file's link on your tailnet, opened in the phone's Safari.",
                               "Para o cadex share: o link de um arquivo na sua tailnet, aberto no Safari do celular."),
                             control: SettingsPage.toggle(store.settings.machines.tailscale) { on in store.update { $0.machines.tailscale = on } }),
            SettingsPage.row(T("Remote Login", "Login Remoto"),
                             T("macOS's SSH server: System Settings › General › Sharing › Remote Login, on, only for your user.",
                               "O servidor SSH do macOS: Ajustes do Sistema › Geral › Compartilhamento › Login Remoto, ligado, só para o seu usuário."),
                             control: SettingsPage.button(T("Open Sharing", "Abrir Compartilhamento")) {
                                 if let url = URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension") { NSWorkspace.shared.open(url) }
                             }),
            commandRow(),
            SettingsPage.section(T("From the phone", "No celular")),
            SettingsPage.row(T("Connect", "Conectar"),
                             "ssh \(NSUserName())@\(macName)\n" + T("In the phone's terminal app, with Tailscale on in the phone, add this Mac as a host (its tailnet name, or its 100.x address from `tailscale ip -4`) and connect. mosh, if installed (`brew install mosh`), keeps the session through a dropped 4G or a locked phone.",
                               "No app de terminal do celular, com o Tailscale ligado nele, cadastre este Mac como host (o nome dele na tailnet, ou o endereço 100.x do `tailscale ip -4`) e conecte. O mosh, se instalado (`brew install mosh`), segura a sessão com o 4G caindo ou o celular bloqueado."),
                             control: copy("ssh \(NSUserName())@\(macName)")),
            SettingsPage.row(T("The menu", "O menu"),
                             T("Type `cadex`: a list of the tabs open in Cadex; a number joins one live (both screens see and type; Ctrl+\\ d leaves). `n` opens a terminal and `c` Claude in a project.",
                               "Digite `cadex`: a lista das abas abertas no Cadex; um número entra numa ao vivo (as duas telas veem e digitam; Ctrl+\\ d sai). `n` abre um terminal e `c` o Claude num projeto."),
                             control: copy("cadex")),
            SettingsPage.row(T("Claude in a project", "O Claude num projeto"),
                             T("Straight in, without the menu: a new tab in the project (by name or the start of it), on the Mac too.",
                               "Direto, sem o menu: uma aba nova no projeto (pelo nome ou o começo dele), no Mac também."),
                             control: copy("cadex new cadex claude")),
            SettingsPage.row(T("See what the agent made", "Ver o que o agente fez"),
                             T("A link valid for an hour on your tailnet, for HTML, images, PDF, Office and Markdown, opened in Safari.",
                               "Um link válido por uma hora na sua tailnet, para HTML, imagem, PDF, Office e Markdown, aberto no Safari."),
                             control: copy("cadex share index.html")),
            SettingsPage.row(T("The whole guide", "O guia completo"),
                             T("Every step, and what each message means.", "Cada passo, e o que cada mensagem quer dizer."),
                             control: SettingsPage.button(T("Open the Guide", "Abrir o guia")) {
                                 if let url = URL(string: "https://github.com/c4duZ/cadex/blob/main/docs/guides/phone.md") { NSWorkspace.shared.open(url) }
                             }),
        ]
    }

    /// This Mac's name as Tailscale names it by default: the computer's name, lowercase, with dashes.
    static var macName: String {
        let name = (Host.current().localizedName ?? ProcessInfo.processInfo.hostName).lowercased()
        let dashed = name.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(dashed).split(separator: "-").joined(separator: "-")
    }

    /// A command with Copy beside it.
    private static func copy(_ command: String) -> NSButton {
        let button = SettingsPage.button(T("Copy", "Copiar")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
        button.toolTip = command
        return button
    }

    /// The `cadex` command in ~/.local/bin, the PATH an SSH session has: a link to the one inside the
    /// app (CADEX_TOOLS), made here instead of typed (the guide's step 3).
    private static func commandRow() -> NSView {
        let link = FileManager.default.homeDirectoryForCurrentUser.path + "/.local/bin/cadex"
        let tools = ProcessInfo.processInfo.environment["CADEX_TOOLS"] ?? ""
        let installed = (try? FileManager.default.destinationOfSymbolicLink(atPath: link)) == tools && !tools.isEmpty
        let words = installed
            ? T("Installed: ~/.local/bin/cadex points to this Cadex, so an SSH session finds it.",
                "Instalado: ~/.local/bin/cadex aponta para este Cadex, e uma sessão SSH o acha.")
            : T("An SSH session needs `cadex` in its PATH: a link in ~/.local/bin to the one inside the app. Make sure ~/.local/bin is in your PATH.",
                "Uma sessão SSH precisa do `cadex` no PATH: um link em ~/.local/bin para o que está dentro do app. Confira se ~/.local/bin está no seu PATH.")
        let button = SettingsPage.button(installed ? T("Installed", "Instalado") : T("Install", "Instalar")) { install(link: link, tools: tools) }
        button.isEnabled = !installed && !tools.isEmpty
        return SettingsPage.row(T("The cadex command", "O comando cadex"), words, control: button)
    }

    /// The link made (an old link replaced, a real file never).
    private static func install(link: String, tools: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: (link as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if (try? fm.destinationOfSymbolicLink(atPath: link)) != nil { try? fm.removeItem(atPath: link) }
        guard !fm.fileExists(atPath: link) else { return NSSound.beep() }
        do { try fm.createSymbolicLink(atPath: link, withDestinationPath: tools) } catch { NSSound.beep() }
    }
}
