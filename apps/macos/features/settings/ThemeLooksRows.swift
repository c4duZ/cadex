import AppKit
import Strings
import Themes

/// The themes page's rows of plan 15, phases B and C: one theme for dark
/// mode and one for light, the accent color, high contrast and how dark the
/// panes without focus are.
@MainActor
enum ThemeLooksRows {
    /// Which themes are in use for dark and for light.
    static func inUse(_ a: Settings.Appearance) -> (dark: String, light: String) {
        (a.darkTheme.isEmpty ? a.theme : a.darkTheme, a.lightTheme.isEmpty ? a.theme : a.lightTheme)
    }

    static func pair(_ store: SettingsStore) -> NSView {
        let a = store.settings.appearance
        let (dark, light) = inUse(a)
        let names = (ThemeStore.shared.darkFamily.name, ThemeStore.shared.lightFamily.name)
        let same = SettingsPage.button(T("Use One Theme", "Usar um tema só")) {
            store.update { $0.appearance.theme = dark; $0.appearance.darkTheme = ""; $0.appearance.lightTheme = "" }
        }
        same.isEnabled = dark != light
        let now = dark == light ? T("Now one theme for both: \(names.0).", "Agora um tema para os dois: \(names.0).")
            : T("Now \(names.0) in dark mode and \(names.1) in light mode.", "Agora \(names.0) no modo escuro e \(names.1) no claro.")
        return SettingsPage.row(T("Dark and light", "Escuro e claro"),
                                T("\(now) To pick a theme for one mode only, filter Dark or Light below and pick it there.",
                                  "\(now) Para escolher um tema só para um modo, filtre Escuros ou Claros abaixo e escolha lá."),
                                control: same)
    }

    static func accent(_ store: SettingsStore) -> NSView {
        let a = store.settings.appearance
        let well = NSColorWell(style: .minimal)
        well.color = (a.accent.isEmpty ? ThemeStore.shared.current.interface.accent : (try? ThemeFile.parse(a.accent, field: "")) ?? RGB(0)).nsColor
        well.isContinuous = false
        well.target = ActionBox.keep(well) { store.update { $0.appearance.accent = AccentPicker.hex(well.color) } }
        well.action = #selector(ActionBox.fire)
        let reset = SettingsPage.button(T("Theme's", "Do tema")) { store.update { $0.appearance.accent = "" } }
        reset.isEnabled = !a.accent.isEmpty
        let controls = NSStackView(views: [reset, well])
        controls.spacing = 8
        well.widthAnchor.constraint(equalToConstant: 44).isActive = true
        return SettingsPage.row(T("Accent color", "Cor de destaque"),
                                T("Paints the active tab, the selection, focus and icons that are on. Text over it turns black or white to stay readable.",
                                  "Pinta a aba ativa, a seleção, o foco e os ícones ligados. O texto por cima vira preto ou branco para continuar legível."),
                                control: controls)
    }

    static func contrast(_ store: SettingsStore) -> [NSView] {
        let a = store.settings.appearance
        return [
            SettingsPage.row(T("High contrast", "Alto contraste"),
                             T("All text at 7:1, stronger borders and focus, no transparency. Also turns on with Increase contrast in the system's Accessibility settings.",
                               "Todo texto a 7:1, bordas e foco mais fortes, sem transparência. Liga também com Aumentar contraste nos ajustes de Acessibilidade do sistema."),
                             control: SettingsPage.toggle(a.highContrast) { on in store.update { $0.appearance.highContrast = on } }),
            SettingsPage.row(T("Panes without focus", "Painéis sem foco"),
                             T("How much darker the other panes of a tab are, so the one you type in stands out. 0 turns it off.",
                               "O quanto os outros painéis de uma aba ficam mais escuros, para destacar aquele em que você digita. 0 desliga."),
                             control: SettingsPage.slider(store.settings.tabs.unfocusedDim, range: Settings.dimRange, format: "%.0f%%", shown: { $0 * 100 }) { value in
                                 store.update { $0.tabs.unfocusedDim = value }
                             }),
        ]
    }
}

/// The accent from ⌘K (theme.accent): the system's color panel, saved when
/// a color is picked.
@MainActor
enum AccentPicker {
    private static var target: ActionBox?

    static func show(_ store: SettingsStore) {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = false
        panel.color = ThemeStore.shared.current.interface.accent.nsColor
        target = ActionBox.keep(panel) { store.update { $0.appearance.accent = hex(panel.color) } }
        panel.setTarget(target)
        panel.setAction(#selector(ActionBox.fire))
        panel.orderFront(nil)
    }

    static func hex(_ color: NSColor) -> String {
        guard let c = color.usingColorSpace(.sRGB) else { return "" }
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}
