import Foundation
import Checks
@testable import Strings

// Tests of the shared texts. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
    ("a text comes in the interface's language and knows its other version", {
        Strings.language = .en
        expect(T("Open file", "Abrir arquivo") == "Open file")
        expect(Strings.counterpart(of: "Open file") == "Abrir arquivo")
        Strings.language = .pt
        expect(T("Open file", "Abrir arquivo") == "Abrir arquivo")
        expect(Strings.counterpart(of: "Abrir arquivo") == "Open file")
        Strings.language = .en
    }),
    ("a text the same in both has no other version", {
        expect(T("Git", "Git") == "Git" && Strings.counterpart(of: "Git") == nil)
    }),
])
exit(exitCode)
