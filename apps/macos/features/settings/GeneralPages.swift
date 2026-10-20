import AppKit
import Strings

/// The "General" and "About" pages (docs/spec/settings.md): rows of
/// controls that change settings.json at once, in sections, each saying
/// what it changes (owner, 2026-10-20: the old texts were badly put).
@MainActor
enum GeneralPages {
    /// askRelaunch: the language changed; it counts when Cadex reopens.
    static func general(_ store: SettingsStore, askRelaunch: @escaping (String) -> Void) -> NSView {
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
            ] + KeepAwakeRows.make(store))
    }

    static func about() -> NSView {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? T("development", "desenvolvimento")
        let credits = NSTextField(wrappingLabelWithString: T(
            "A terminal-centered development workspace, native, with its own code under the MIT license. The terminal model is libghostty-vt; the icons are Phosphor; the themes come from tweakcn and from the official palettes of open themes. Full credits in the NOTICE file.",
            "Workspace de desenvolvimento centrado no terminal, nativo, com código próprio sob a licença MIT. O modelo do terminal é a libghostty-vt; os ícones são Phosphor; os temas vêm do tweakcn e das paletas oficiais de temas abertos. Créditos completos no arquivo NOTICE."))
        credits.textColor = SettingsColors.secondaryText
        return SettingsPage.make(title: "Cadex", subtitle: T("Version", "Versão") + " \(version)", rows: [credits])
    }
}
