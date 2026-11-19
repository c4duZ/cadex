import CCadex
import Checks
import Foundation
@testable import Terminal

/// A screen of plain rows (`flagged` rows get CADEX_CELL_INPUT from `inputFrom` on, to the text's end).
private func screen(_ lines: [String], cols: Int = 30, input: (row: Int, from: Int)? = nil) -> WrittenScreen {
    var text: [String] = [], flags: [UInt16] = []
    for (row, line) in lines.enumerated() {
        let chars = Array(line).map(String.init)
        for col in 0..<cols {
            text.append(col < chars.count ? chars[col] : " ")
            let typed = input.map { row == $0.row && col >= $0.from && col < chars.count } ?? false
            flags.append(typed ? UInt16(CADEX_CELL_INPUT) : 0)
        }
    }
    return WrittenScreen(cols: cols, rows: lines.count, text: text, flags: flags)
}

@MainActor let inputFieldChecks: [(name: String, body: Checks.Body)] = [
    ("Claude's input: the text after \"❯ \" in the last box, its rows, and the Backspaces to clear it", {
        let rule = String(repeating: "─", count: 30)
        let s = screen(["⏺ Done.", "", rule, "❯\u{00A0}fix the tests", "  and the docs", rule, "  Opus 5.5"])
        let field = s.claudeInput()
        expect(field?.kind == .claude && field?.rows == 3...4, "\(String(describing: field))")
        expect(field?.start == .init(row: 3, col: 2) && field?.end == .init(row: 4, col: 13), "\(String(describing: field))")
        expect(s.eraseCount(field!) >= "fix the tests".count + "  and the docs".count, "\(s.eraseCount(field!))")
        let empty = screen([rule, "❯\u{00A0}", rule]).claudeInput()
        expect(empty?.isEmpty == true, "an empty prompt selects nothing")
    }),
    ("the shell's input: the marked cells on the cursor's row, not the prompt", {
        let s = screen(["~/cadex % ls -la", "x"], input: (row: 0, from: 10))
        let field = s.shellInput(cursorRow: 0)
        expect(field?.kind == .shell && field?.start == .init(row: 0, col: 10) && field?.end == .init(row: 0, col: 15), "\(String(describing: field))")
        expect(s.shellInput(cursorRow: 1) == nil, "a row with nothing typed")
        var twice = screen(["~/cadex % print -z x", "~/cadex % echo hi"], input: (row: 1, from: 10))
        for col in 10..<20 { twice.flags[col] = UInt16(CADEX_CELL_INPUT) }
        expect(twice.shellInput(cursorRow: 1)?.rows == 1...1, "the command before, typed too, stays out")
    }),
    ("a paragraph: the rows with text around the row, up to a blank row or a rule", {
        let rule = String(repeating: "─", count: 30)
        let s = screen(["first", "", "a long", "paragraph here", "", "after", rule, "❯\u{00A0}x", rule])
        let p = s.paragraph(row: 3)
        expect(p?.start == .init(row: 2, col: 0) && p?.end == .init(row: 3, col: 13), "\(String(describing: p))")
        expect(s.paragraph(row: 1) == nil, "a blank row has none")
        expect(s.paragraph(row: 5)?.end.row == 5, "a rule ends a paragraph")
    }),
]
