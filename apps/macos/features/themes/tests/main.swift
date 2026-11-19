import Checks
import Foundation
@testable import Themes

// Tests of the themes feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

/// A light theme from the catalog, for the checks that need one.
let lightTheme = ThemeCatalog.family(id: "gruvbox")!.light!

let exitCode = await Checks.run([
    ("Cadex Night, generated from the mockups' tokens, has the 16 ANSI colors and only a dark version", {
        expect(Theme.cadexNight.terminal.ansi.count == 16)
        expect(Theme.cadexNight.dark && ThemeFamily.cadexNight.light == nil)
        expect(Theme.cadexNight.interface.chrome == RGB(0x121316), "bg.chrome of tokens.json")
    }),
    ("a theme file reads back what was written", {
        let data = ThemeFile.write(.cadexNight)
        expect(try ThemeFile.read(data) == .cadexNight)
    }),
    ("an invalid color is refused with the field in the message", {
        var object = try JSONSerialization.jsonObject(with: ThemeFile.write(.cadexNight)) as! [String: Any]
        var terminal = object["terminal"] as! [String: Any]
        terminal["cursor"] = "vermelho"
        object["terminal"] = terminal
        do {
            _ = try ThemeFile.read(try JSONSerialization.data(withJSONObject: object))
            expect(false, "accepted an invalid color")
        } catch let problem as ThemeFile.Problem {
            expect(problem.field == "terminal.cursor", problem.description)
        }
    }),
    ("short forms of colors and a short ANSI list", {
        expect(try ThemeFile.parse("#fff", field: "x") == RGB(0xFFFFFF))
        expect(try ThemeFile.parse("#12345678", field: "x") == RGB(0x123456))
        expect((try? ThemeFile.parse("123456", field: "x")) == nil)
        var object = try JSONSerialization.jsonObject(with: ThemeFile.write(.cadexNight)) as! [String: Any]
        var terminal = object["terminal"] as! [String: Any]
        terminal["ansi"] = ["#000000"]
        object["terminal"] = terminal
        expect((try? ThemeFile.read(try JSONSerialization.data(withJSONObject: object))) == nil)
    }),
    ("the built-in catalog: the official themes, Cadex Night first and the default", {
        let families = ThemeCatalog.all()
        expect(families.count > 30 && families.allSatisfy { $0.source == "official" || $0.source == "cadex" }, "\(families.count)")
        expect(families.first?.id == "cadex-night" && ThemeCatalog.defaultId == "cadex-night")
        expect(ThemeCatalog.family(id: "caffeine") == nil, "the tweakcn presets left on 2026-11-17")
        expect(Set(families.map(\.id)).count == families.count, "repeated ids")
        for family in families {
            expect(family.dark != nil || family.light != nil, family.id)
            expect(!family.description.isEmpty, family.id)
        }
        expect(families.first { $0.id == "nord" }?.light == nil, "Nord has no light version")
        expect(ThemeCatalog.family(id: "gruvbox")?.light != nil)
        expect(ThemeCatalog.family(id: "nope") == nil)
    }),
    ("Cadex Day: light only, second, its ANSI readable on its ground", {
        expect(ThemeCatalog.all().dropFirst().first?.id == "cadex-day" && ThemeFamily.cadexDay.dark == nil)
        expect(ThemeCatalog.family(id: "cadex-day") == .cadexDay)
        let day = Theme.cadexDay.terminal
        for (i, color) in day.ansi.enumerated() where ![0, 7, 8, 15].contains(i) {
            expect(color.contrast(with: day.background) >= 4.5, "ansi \(i) \(color.hex)")
        }
    }),
    ("the frame sits on the terminal's ground: no box around the terminal", {
        let github = ThemeCatalog.family(id: "github")!.theme(dark: false)
        expect(github.interface.chrome != github.terminal.background, "the catalog's frame is a shade off")
        let grounded = github.onTerminalGround()
        expect(grounded.interface.chrome == github.terminal.background && grounded.terminal == github.terminal)
        expect(Theme.cadexNight.onTerminalGround() == .cadexNight, "Night already is")
    }),
    ("every built-in theme's text is readable", {
        for family in ThemeCatalog.all() {
            for theme in [family.dark, family.light].compactMap({ $0 }) {
                let ui = theme.interface, term = theme.terminal
                expect(term.foreground.contrast(with: term.background) >= 4.0, "\(family.id) terminal")
                expect(ui.text.contrast(with: ui.panel) >= 4.5, "\(family.id) text")
                expect(ui.secondaryText.contrast(with: ui.panel) >= 3.0, "\(family.id) secondary text")
            }
        }
    }),
    ("a Ghostty, an iTerm2 and a base16 theme are imported", {
        let ghostty = (["background = 1d1f21", "foreground = #c5c8c6", "cursor-color = #c5c8c6"]
            + (0..<16).map { "palette = \($0)=#\(String(format: "%02x%02x%02x", $0 * 10, 100, 200))" }).joined(separator: "\n")
        let fromGhostty = try ThemeImport.ghostty(ghostty, name: "Test")
        expect(fromGhostty.dark && fromGhostty.terminal.background == RGB(0x1D1F21))
        expect(fromGhostty.terminal.ansi[4] == RGB(0x2864C8) && fromGhostty.interface.accent == RGB(0x2864C8))
        var plist: [String: Any] = [:]
        func color(_ r: Double, _ g: Double, _ b: Double) -> [String: Any] { ["Red Component": r, "Green Component": g, "Blue Component": b] }
        for i in 0..<16 { plist["Ansi \(i) Color"] = color(Double(i) / 15, 0, 0) }
        plist["Background Color"] = color(1, 1, 1)
        plist["Foreground Color"] = color(0, 0, 0)
        let iterm = try ThemeImport.iterm(try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0), name: "Light")
        expect(!iterm.dark && iterm.terminal.ansi[15] == RGB(0xFF0000))
        let yaml = "system: \"base16\"\nname: \"Mine\"\npalette:\n" + (0..<16).map { String(format: "  base%02X: \"#%02x%02x%02x\" # c", $0, $0 * 16, $0 * 16, $0 * 16) }.joined(separator: "\n")
        let base16 = try ThemeImport.base16(yaml, name: "x")
        expect(base16.name == "Mine" && base16.terminal.background == RGB(0x000000) && base16.terminal.ansi[9] == RGB(0x808080))
    }),
    ("a theme saved in the folder is found by its id", {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cadex-themes-\(UUID().uuidString)")
        setenv("CADEX_THEMES_DIR", folder.path, 1)
        defer { try? FileManager.default.removeItem(at: folder); unsetenv("CADEX_THEMES_DIR") }
        var theme = lightTheme
        theme.name = "Meu Tema!"
        let id = try ThemeLibrary.save(theme)
        expect(id == "user:meu-tema", id)
        expect(ThemeLibrary.family(id: id)?.light?.name == "Meu Tema!")
        try Data("{".utf8).write(to: folder.appendingPathComponent("broken.json"))
        let all = ThemeLibrary.all()
        expect(all.families.first?.id == id && all.problems.count == 1 && all.problems[0].hasPrefix("broken.json"))
    }),
    ("high contrast puts every text at 7:1 and borders at 3:1", {
        for family in ThemeCatalog.all() {
            for theme in [family.dark, family.light].compactMap({ $0 }) {
                let ui = theme.withHighContrast().interface
                for bg in [ui.panel, ui.chrome, ui.field] {
                    expect(ui.text.contrast(with: bg) >= 6.95 && ui.secondaryText.contrast(with: bg) >= 6.95, "\(family.id)")
                }
                expect(ui.panelBorder.contrast(with: ui.panel) >= 2.95, "\(family.id) border")
                let terminal = theme.withHighContrast().terminal
                expect(terminal.foreground.contrast(with: terminal.background) >= 6.95, family.id)
            }
        }
    }),
    ("text over a light accent turns dark, over a dark one light", {
        var light = Theme.cadexNight.interface
        light.tabActive = RGB(0xF5E663)
        expect(light.textOnTabActive == RGB(0x000000))
        var dark = lightTheme.interface
        dark.tabActive = RGB(0x1A237E)
        expect(dark.textOnTabActive == RGB(0xFFFFFF))
        expect(Theme.cadexNight.interface.textOnTabActive == Theme.cadexNight.interface.text)
    }),
    ("colors print as #RRGGBB", {
        expect(RGB(0x252525).hex == "#252525")
        expect(RGB(0x1FFFFFF).value == 0xFFFFFF)
    }),
])
exit(exitCode)
