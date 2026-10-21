import AppKit
import Strings

/// The terminal page's reading rows (plan 15, phase C): minimum contrast,
/// line height, letter spacing, ligatures and the font's other features.
@MainActor
enum TerminalTextRows {
    static let ligatures = ["calt", "liga"]

    static func make(_ store: SettingsStore) -> [NSView] {
        let t = store.settings.terminal
        let others = t.fontFeatures.filter { !ligatures.contains($0) }
        return [
            SettingsPage.section(T("Reading", "Leitura")),
            SettingsPage.row(T("Minimum contrast", "Contraste mínimo"),
                             T("Text a program colors too close to its background is moved toward white or black until it reads. 1 leaves the colors alone; 4.5 is the usual minimum for text, 7 is high contrast.",
                               "Texto que um programa pinta perto demais do fundo vai para o branco ou o preto até dar para ler. 1 deixa as cores como estão; 4,5 é o mínimo usual para texto, 7 é alto contraste."),
                             control: SettingsPage.slider(t.minimumContrast, range: Settings.contrastRange, format: "%.1f:1") { value in
                                 store.update { $0.terminal.minimumContrast = (value * 2).rounded() / 2 }
                             }),
            SettingsPage.row(T("Line height", "Altura da linha"),
                             T("Space between lines, as a multiple of the font's own.", "O espaço entre as linhas, em vezes o da própria fonte."),
                             control: SettingsPage.number(t.lineHeight, range: Settings.lineHeights, step: 0.05, format: "%.2f×") { value in
                                 store.update { $0.terminal.lineHeight = value }
                             }),
            SettingsPage.row(T("Letter spacing", "Espaçamento entre letras"),
                             T("Extra space between letters, in points. Below zero brings them closer.",
                               "Espaço a mais entre as letras, em pontos. Abaixo de zero aproxima."),
                             control: SettingsPage.number(t.letterSpacing, range: Settings.letterSpacings, step: 0.25, format: "%.2f pt") { value in
                                 store.update { $0.terminal.letterSpacing = value }
                             }),
            SettingsPage.row(T("Ligatures", "Ligaduras"),
                             T("With a font that has them, such as Fira Code or JetBrains Mono, -> and != join into one sign.",
                               "Com uma fonte que as tem, como Fira Code ou JetBrains Mono, -> e != viram um sinal só."),
                             control: SettingsPage.toggle(ligatures.allSatisfy(t.fontFeatures.contains)) { on in
                                 store.update { $0.terminal.fontFeatures = setLigatures(on, in: $0.terminal.fontFeatures) }
                             }),
            SettingsPage.row(T("Font features", "Recursos da fonte"),
                             T("OpenType features, separated by commas: ss01 for a stylistic set, zero for a slashed zero, -liga to turn one off.",
                               "Recursos OpenType, separados por vírgula: ss01 para um conjunto de estilo, zero para o zero cortado, -liga para desligar um."),
                             control: SettingsPage.text(others.joined(separator: ", "), placeholder: "ss01, zero") { text in
                                 let list = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter(Settings.isFontFeature)
                                 store.update { $0.terminal.fontFeatures = $0.terminal.fontFeatures.filter(ligatures.contains) + list }
                             }),
        ]
    }

    static func setLigatures(_ on: Bool, in features: [String]) -> [String] {
        let rest = features.filter { !ligatures.contains($0) }
        return on ? ligatures + rest : rest
    }
}
