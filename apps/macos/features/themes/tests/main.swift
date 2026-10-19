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
    ("colors print as #RRGGBB", {
        expect(RGB(0x252525).hex == "#252525")
        expect(RGB(0x1FFFFFF).value == 0xFFFFFF)
    }),
])
exit(exitCode)
