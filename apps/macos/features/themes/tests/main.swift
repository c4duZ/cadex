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
    ("the built-in catalog has the 46 themes, Caffeine first", {
        let families = ThemeCatalog.builtIn
        expect(families.count == 46, "\(families.count)")
        expect(families.first?.id == "caffeine")
        expect(Set(families.map(\.id)).count == families.count, "repeated ids")
        for family in families {
            expect(family.dark != nil || family.light != nil, family.id)
            expect(!family.description.isEmpty, family.id)
        }
        expect(families.first { $0.id == "nord" }?.light == nil, "Nord has no light version")
    }),
    ("colors print as #RRGGBB", {
        expect(RGB(0x252525).hex == "#252525")
        expect(RGB(0x1FFFFFF).value == 0xFFFFFF)
    }),
])
exit(exitCode)
