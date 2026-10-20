import AppKit

/// The "Geral" and "Terminal" pages (docs/spec/settings.md): rows of
/// controls that change settings.json at once.
@MainActor
enum GeneralPages {
    static func general(_ store: SettingsStore) -> NSView {
        let g = store.settings.general
        return SettingsPage.make(title: "Geral", subtitle: "Shell, as perguntas antes de agir e onde abrem os arquivos e as notas.", rows: [
            SettingsPage.row("Shell", "Vazio usa o shell do sistema. Vale para terminais novos.",
                             control: SettingsPage.text(g.shell, placeholder: "/bin/zsh") { value in
                                 store.update { $0.general.shell = value.trimmingCharacters(in: .whitespaces) }
                             }),
            SettingsPage.row("Perguntar antes de fechar", "Com um programa rodando no painel, na aba ou na janela.",
                             control: SettingsPage.toggle(g.confirmClose) { on in store.update { $0.general.confirmClose = on } }),
            SettingsPage.row("Perguntar antes de colar várias linhas", "Quando o programa não marca colagens e cada linha rodaria.",
                             control: SettingsPage.toggle(g.confirmMultilinePaste) { on in
                                 store.update { $0.general.confirmMultilinePaste = on }
                             }),
            SettingsPage.row("Abrir arquivos", "Ao lado do painel com foco, na mesma aba, ou numa aba nova. \"Abrir ao lado\" e \"Abrir em nova aba\" escolhem na hora.",
                             control: SettingsPage.popup([("Ao lado", "beside"), ("Em nova aba", "tab")], selected: g.openFiles) { value in
                                 store.update { $0.general.openFiles = value }
                             }),
            SettingsPage.row("A árvore segue o terminal", "Ao mudar de pasta no terminal, a árvore vai para o projeto dela (a raiz do repositório git, ou a própria pasta).",
                             control: SettingsPage.toggle(store.settings.explorer.followTerminal) { on in
                                 store.update { $0.explorer.followTerminal = on }
                             }),
            SettingsPage.row("Abrir Markdown como", "Código para editar, ou já renderizado. O botão no canto da aba troca a qualquer hora.",
                             control: SettingsPage.popup([("Código", "source"), ("Renderizado", "rendered")],
                                                         selected: store.settings.markdown.openAs) { value in
                                 store.update { $0.markdown.openAs = value }
                             }),
            SettingsPage.row("Manter acordado ao abrir", "Como o Cadex abre: deixando o computador dormir, sempre acordado, ou acordado só com um programa rodando no terminal. O ícone de café na barra e o ⌘K mudam na hora.",
                             control: SettingsPage.popup([("Não", "off"), ("Sempre", "always"), ("Com programa rodando", "running")],
                                                         selected: store.settings.power.keepAwake) { value in
                                 store.update { $0.power.keepAwake = value }
                             }),
            SettingsPage.row("Manter a tela acesa", "Desligado, a tela pode apagar e o computador segue rodando. Na tomada, segue rodando também com a tampa fechada.",
                             control: SettingsPage.toggle(store.settings.power.keepDisplayOn) { on in
                                 store.update { $0.power.keepDisplayOn = on }
                             }),
        ])
    }

    static func terminal(_ store: SettingsStore) -> NSView {
        let t = store.settings.terminal
        let fonts = ["SF Mono"] + NSFontManager.shared.availableFontFamilies.filter { family in
            NSFont(name: family, size: 12)?.isFixedPitch == true && family != "SF Mono"
        }
        return SettingsPage.make(title: "Terminal", subtitle: "Fonte, cursor, histórico e teclado.", rows: [
            SettingsPage.row("Fonte", nil, control: SettingsPage.popup(fonts.map { ($0, $0) }, selected: t.fontFamily) { family in
                store.update { $0.terminal.fontFamily = family }
            }),
            SettingsPage.row("Tamanho", "De 8 a 32 pt.",
                             control: SettingsPage.number(t.fontSize, range: Settings.fontSizes, step: 1, format: "%.0f pt") { size in
                                 store.update { $0.terminal.fontSize = size }
                             }),
            SettingsPage.row("Cursor", "O programa ainda pode escolher outro (o vim faz isso).",
                             control: SettingsPage.popup([("Barra", "bar"), ("Bloco", "block"), ("Sublinhado", "underline")],
                                                         selected: t.cursor) { value in store.update { $0.terminal.cursor = value } }),
            SettingsPage.row("Cursor piscando", nil,
                             control: SettingsPage.toggle(t.cursorBlink) { on in store.update { $0.terminal.cursorBlink = on } }),
            SettingsPage.row("Linhas de histórico", "Vale para terminais novos. Até 100 mil.",
                             control: SettingsPage.number(Double(t.historyLines), range: 1_000...100_000, step: 1_000, format: "%.0f") { lines in
                                 store.update { $0.terminal.historyLines = Int(lines) }
                             }),
            SettingsPage.row("Option esquerdo como Meta", "Option+B vai ao shell como Meta+B em vez de digitar ∫.",
                             control: SettingsPage.toggle(t.optionAsMeta) { on in store.update { $0.terminal.optionAsMeta = on } }),
            SettingsPage.row("Copiar ao selecionar", "Desligado, só ⌘C muda a área de transferência.",
                             control: SettingsPage.toggle(t.copyOnSelect) { on in store.update { $0.terminal.copyOnSelect = on } }),
        ])
    }

    static func about() -> NSView {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "desenvolvimento"
        let credits = NSTextField(wrappingLabelWithString:
            "Workspace de desenvolvimento centrado no terminal, nativo, com código próprio sob a licença MIT. " +
            "O modelo do terminal é a libghostty-vt; os ícones são Phosphor; os temas vêm do tweakcn e das " +
            "paletas oficiais de temas abertos. Créditos completos no arquivo NOTICE.")
        credits.textColor = SettingsColors.secondaryText
        return SettingsPage.make(title: "Cadex", subtitle: "Versão \(version)", rows: [credits])
    }
}
