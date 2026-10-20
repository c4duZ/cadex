import AppKit
import Strings

/// The "Terminal" page: the shell and the questions before closing or
/// pasting (in General before 2026-10-20), the text and cursor, history
/// and keyboard.
@MainActor
enum TerminalPage {
    static func make(_ store: SettingsStore) -> NSView {
        let g = store.settings.general
        let t = store.settings.terminal
        let fonts = ["SF Mono"] + NSFontManager.shared.availableFontFamilies.filter { family in
            NSFont(name: family, size: 12)?.isFixedPitch == true && family != "SF Mono"
        }
        return SettingsPage.make(
            title: "Terminal",
            subtitle: T("The shell, the questions before closing or pasting, the text and the keyboard.",
                        "O shell, as perguntas antes de fechar ou colar, o texto e o teclado."),
            rows: [
                SettingsPage.section("Shell"),
                SettingsPage.row("Shell",
                                 T("The program each new terminal runs. Empty uses your login shell.",
                                   "O programa que cada terminal novo roda. Vazio usa o shell do seu usuário."),
                                 control: SettingsPage.text(g.shell, placeholder: "/bin/zsh") { value in
                                     store.update { $0.general.shell = value.trimmingCharacters(in: .whitespaces) }
                                 }),
                SettingsPage.row(T("Ask before closing a running program", "Perguntar antes de fechar um programa rodando"),
                                 T("Closing a pane, tab or window where a program is running, such as a server or an agent, asks first.",
                                   "Fechar um painel, aba ou janela com um programa rodando, como um servidor ou um agente, pergunta antes."),
                                 control: SettingsPage.toggle(g.confirmClose) { on in store.update { $0.general.confirmClose = on } }),
                SettingsPage.row(T("Ask before pasting several lines", "Perguntar antes de colar várias linhas"),
                                 T("Where the program does not protect pastes, each line would run as a command. Asks first.",
                                   "Onde o programa não protege a colagem, cada linha rodaria como um comando. Pergunta antes."),
                                 control: SettingsPage.toggle(g.confirmMultilinePaste) { on in
                                     store.update { $0.general.confirmMultilinePaste = on }
                                 }),

                SettingsPage.section(T("Text and cursor", "Texto e cursor")),
                SettingsPage.row(T("Font", "Fonte"), T("Fixed-width fonts installed on this Mac.", "As fontes de largura fixa instaladas neste Mac."),
                                 control: SettingsPage.popup(fonts.map { ($0, $0) }, selected: t.fontFamily) { family in
                                     store.update { $0.terminal.fontFamily = family }
                                 }),
                SettingsPage.row(T("Size", "Tamanho"), T("From 8 to 32 points.", "De 8 a 32 pontos."),
                                 control: SettingsPage.number(t.fontSize, range: Settings.fontSizes, step: 1, format: "%.0f pt") { size in
                                     store.update { $0.terminal.fontSize = size }
                                 }),
                SettingsPage.row(T("Cursor", "Cursor"),
                                 T("Programs such as vim may pick another one while they run.",
                                   "Programas como o vim podem escolher outro enquanto rodam."),
                                 control: SettingsPage.popup([(T("Bar", "Barra"), "bar"), (T("Block", "Bloco"), "block"),
                                                              (T("Underline", "Sublinhado"), "underline")],
                                                             selected: t.cursor) { value in store.update { $0.terminal.cursor = value } }),
                SettingsPage.row(T("Blinking cursor", "Cursor piscando"), nil,
                                 control: SettingsPage.toggle(t.cursorBlink) { on in store.update { $0.terminal.cursorBlink = on } }),

                SettingsPage.section(T("History and keyboard", "Histórico e teclado")),
                SettingsPage.row(T("History lines", "Linhas de histórico"),
                                 T("How far back you can scroll, up to 100,000 lines. Counts for new terminals.",
                                   "Até onde dá para rolar para trás, até 100 mil linhas. Vale para terminais novos."),
                                 control: SettingsPage.number(Double(t.historyLines), range: 1_000...100_000, step: 1_000, format: "%.0f") { lines in
                                     store.update { $0.terminal.historyLines = Int(lines) }
                                 }),
                SettingsPage.row(T("Left Option as Meta", "Option esquerdo como Meta"),
                                 T("Option+B reaches the shell as Meta+B (back one word) instead of typing ∫.",
                                   "Option+B chega ao shell como Meta+B (volta uma palavra) em vez de digitar ∫."),
                                 control: SettingsPage.toggle(t.optionAsMeta) { on in store.update { $0.terminal.optionAsMeta = on } }),
                SettingsPage.row(T("Copy on select", "Copiar ao selecionar"),
                                 T("Selecting text copies it. Off, only ⌘C copies.", "Selecionar um texto já copia. Desligado, só o ⌘C copia."),
                                 control: SettingsPage.toggle(t.copyOnSelect) { on in store.update { $0.terminal.copyOnSelect = on } }),
            ])
    }
}
