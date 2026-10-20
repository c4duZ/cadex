import AppKit
import Strings

/// Keep awake's sections in General (docs/spec/power.md): the options
/// lost among the other rows, so they get sections of their own; a page
/// apart was too much (owner, 2026-10-20). Each row says what it changes;
/// the lid is explained apart, not inside a toggle.
@MainActor
enum KeepAwakeRows {
    static func make(_ store: SettingsStore) -> [NSView] {
        let p = store.settings.power
        return [
            SettingsPage.section(T("Keep awake", "Manter acordado")),
            SettingsPage.note(T(
                "Keeps the computer from sleeping while your work runs. The coffee in the title bar, the Cadex icon in the menu bar and ⇧⌘A turn it on and off; ⌘K can also turn on either mode.",
                "Impede o computador de dormir enquanto o seu trabalho roda. O café na barra de título, o ícone do Cadex na barra de menus e o ⇧⌘A ligam e desligam; o ⌘K também liga qualquer um dos modos.")),
            SettingsPage.row(T("Mode", "Modo"),
                             T("Always: awake until you turn it off. While a program runs: awake only while a terminal runs something, such as an agent, a build or a server; once they all finish, the computer sleeps as usual.",
                               "Sempre: acordado até você desligar. Com programa rodando: acordado só enquanto algum terminal roda alguma coisa, como um agente, um build ou um servidor; quando todos terminam, o computador dorme como sempre."),
                             control: SettingsPage.popup([(T("Always", "Sempre"), "always"),
                                                          (T("While a program runs", "Com programa rodando"), "running")],
                                                         selected: p.mode) { value in store.update { $0.power.mode = value } }),
            SettingsPage.row(T("Keep the screen on", "Manter a tela acesa"),
                             T("Off, the screen turns off as usual and the computer keeps running. On, the screen stays on too.",
                               "Desligado, a tela apaga como sempre e o computador segue rodando. Ligado, a tela também fica acesa."),
                             control: SettingsPage.toggle(p.keepDisplayOn) { on in store.update { $0.power.keepDisplayOn = on } }),
            SettingsPage.row(T("Turn on when Cadex opens", "Ligar ao abrir o Cadex"),
                             T("Cadex opens with keep awake already on, in the mode above.",
                               "O Cadex abre com o manter acordado já ligado, no modo acima."),
                             control: SettingsPage.toggle(p.onAtLaunch) { on in store.update { $0.power.onAtLaunch = on } }),
            SettingsPage.note(T(
                "Closed lid: plugged in, the Mac keeps running with the lid closed while keep awake is on. On battery, macOS sleeps when you close the lid, whatever Cadex asks.",
                "Tampa fechada: na tomada, o Mac segue rodando com a tampa fechada enquanto o manter acordado está ligado. Na bateria, o macOS dorme ao fechar a tampa, não importa o que o Cadex peça.")),
        ]
    }
}
