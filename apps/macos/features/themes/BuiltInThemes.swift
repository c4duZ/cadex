/// The themes that come with the app (docs/spec/themes.md).
public extension Theme {
    /// Dark, in the style of Terax: graphite chrome around near-black
    /// panels. Interface colors measured from a print of Terax (2026-10-19);
    /// the ANSI palette is the Cadex's own.
    static let cadexDark = Theme(
        name: "Cadex Escuro", dark: true,
        interface: Interface(
            chrome: RGB(0x252525), panel: RGB(0x161616), panelBorder: RGB(0x2E2E2E),
            tabActive: RGB(0x383838), field: RGB(0x2C2C2C), text: RGB(0xE6E6E6),
            secondaryText: RGB(0x8E8E8E), accent: RGB(0x8B93E6)),
        terminal: Terminal(
            background: RGB(0x161616), foreground: RGB(0xD6D6D6), cursor: RGB(0xE6E6E6),
            selection: RGB(0x3D4A6B),
            ansi: [0x1E1E1E, 0xE5636E, 0x8CC570, 0xE2C06B, 0x6CA5F0, 0xC27BE0, 0x5FC3C9, 0xC8C8C8,
                   0x5C5C5C, 0xF07A84, 0xA3D98A, 0xF0D388, 0x8DBBF7, 0xD59AEC, 0x7DD6DB, 0xF2F2F2].map(RGB.init)))

    /// Light, the same layout in daylight colors.
    static let cadexLight = Theme(
        name: "Cadex Claro", dark: false,
        interface: Interface(
            chrome: RGB(0xE7E7E7), panel: RGB(0xFFFFFF), panelBorder: RGB(0xD6D6D6),
            tabActive: RGB(0xFFFFFF), field: RGB(0xF4F4F4), text: RGB(0x1F1F1F),
            secondaryText: RGB(0x6B6B6B), accent: RGB(0x4C5BD4)),
        terminal: Terminal(
            background: RGB(0xFFFFFF), foreground: RGB(0x1F1F1F), cursor: RGB(0x1F1F1F),
            selection: RGB(0xC9D5F2),
            ansi: [0x1F1F1F, 0xC4323F, 0x3C8C2C, 0x9C7A10, 0x2F62C8, 0x9B3FB8, 0x1F8A92, 0xBDBDBD,
                   0x6B6B6B, 0xD9505C, 0x4FA63C, 0xB8921E, 0x4A7DE0, 0xB45BD0, 0x2FA3AB, 0xE6E6E6].map(RGB.init)))
}
