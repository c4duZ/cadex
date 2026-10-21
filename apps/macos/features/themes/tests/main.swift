import Checks
import Foundation
@testable import Themes

// Tests of the themes feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
    ("the built-in themes have the 16 ANSI colors", {
        for theme in [Theme.cadexDark, Theme.cadexLight] {
            expect(theme.terminal.ansi.count == 16, theme.name)
        }
        expect(Theme.cadexDark.dark && !Theme.cadexLight.dark)
    }),
    ("a theme file reads back what was written", {
        let data = ThemeFile.write(.cadexDark)
        expect(try ThemeFile.read(data) == .cadexDark)
    }),
    ("an invalid color is refused with the field in the message", {
        var object = try JSONSerialization.jsonObject(with: ThemeFile.write(.cadexLight)) as! [String: Any]
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
        var object = try JSONSerialization.jsonObject(with: ThemeFile.write(.cadexLight)) as! [String: Any]
        var terminal = object["terminal"] as! [String: Any]
        terminal["ansi"] = ["#000000"]
        object["terminal"] = terminal
        expect((try? ThemeFile.read(try JSONSerialization.data(withJSONObject: object))) == nil)
    }),
    ("the built-in catalog has hundreds of themes, Caffeine first", {
        let families = ThemeCatalog.all()
        expect(families.count > 300, "\(families.count)")
        expect(families.first?.id == "caffeine")
        expect(Set(families.map(\.id)).count == families.count, "repeated ids")
        for family in families {
            expect(family.dark != nil || family.light != nil, family.id)
            expect(!family.description.isEmpty, family.id)
        }
        expect(families.first { $0.id == "nord" }?.light == nil, "Nord has no light version")
        expect(ThemeCatalog.family(id: "gruvbox")?.light != nil)
        expect(ThemeCatalog.family(id: "nope") == nil)
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
    ("the tweakcn themes have their own terminal colors", {
        let families = ThemeCatalog.all().filter { $0.source == "tweakcn" }
        let greens = Set(families.compactMap { $0.dark?.terminal.ansi[2] })
        expect(greens.count > families.count / 2, "\(greens.count) greens for \(families.count) themes")
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
        var theme = Theme.cadexLight
        theme.name = "Meu Tema!"
        let id = try ThemeLibrary.save(theme)
        expect(id == "user:meu-tema", id)
        expect(ThemeLibrary.family(id: id)?.light?.name == "Meu Tema!")
        try Data("{".utf8).write(to: folder.appendingPathComponent("broken.json"))
        let all = ThemeLibrary.all()
        expect(all.families.first?.id == id && all.problems.count == 1 && all.problems[0].hasPrefix("broken.json"))
    }),
    ("colors print as #RRGGBB", {
        expect(RGB(0x252525).hex == "#252525")
        expect(RGB(0x1FFFFFF).value == 0xFFFFFF)
    }),
])
exit(exitCode)
