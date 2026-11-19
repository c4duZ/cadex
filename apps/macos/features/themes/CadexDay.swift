import Strings

/// Cadex Day, the light Cadex theme (owner, 2026-11-18): Cadex Night's idea in daylight, neutral
/// grays with color only for state. The frame and the terminal share one ground, so the terminal
/// never shows as a box inside the window; the frame's other colors come from the recipes
/// (tools/design/theme_recipes.py). Hand-made: there is no light mockup yet to generate it from.
public extension Theme {
    static let cadexDay = Theme(
        name: "Cadex Day", dark: false,
        interface: Interface(
            chrome: RGB(0xF9F9FA), panel: RGB(0xF9F9FA), panelBorder: RGB(0xE1E3E6),
            tabActive: RGB(0xECEDEF), field: RGB(0xF1F2F4), text: RGB(0x1D1F23),
            secondaryText: RGB(0x5F646C), accent: RGB(0x2F6FDB)),
        terminal: Terminal(
            background: RGB(0xF9F9FA), foreground: RGB(0x2A2D33), cursor: RGB(0x2A2D33),
            selection: RGB(0xD6E2F5),
            // Darker than Night's, to read on white: each at 4.5:1 or more (the brights too) but the
            // "white" pair, which programs use for faint text.
            ansi: [0x2A2D33, 0xA9322D, 0x22663F, 0x845207, 0x2559B8, 0x6A3DA8, 0x165F69, 0x8A8F98,
                   0x5F646C, 0xC4443E, 0x2B7D4E, 0x9D6209, 0x376FCA, 0x8858C9, 0x207D85, 0xB5B9C0].map(RGB.init)))
}

public extension ThemeFamily {
    /// Only light; Cadex Night stays only dark, so following the system keeps the owner's theme.
    static let cadexDay = ThemeFamily(
        id: "cadex-day", name: "Cadex Day",
        description: T("Neutral light grays; color only for state. Cadex Night in daylight.",
                       "Cinzas claros neutros; cor só para estado. O Cadex Night de dia."),
        source: "cadex", dark: nil, light: Theme.cadexDay)
}
