import CCadex
import Checks
import Foundation
@testable import Terminal

/// ClaudeDress (plan 33) on screens built with the colors and shapes measured on Claude Code
/// 2.1.327 (docs/spec/terminal.md, "As cores e as formas do Claude Code").
struct FakeScreen {
    let cols: Int
    var rows: [[(text: String, fg: UInt32, bg: UInt32?)]] = []

    /// A row: each run of text in its colors, padded with blanks to the width.
    mutating func row(_ runs: (String, UInt32, UInt32?)...) {
        var cells: [(String, UInt32, UInt32?)] = []
        for (text, fg, bg) in runs { for ch in text { cells.append((String(ch), fg, bg)) } }
        let pad = runs.last?.2
        while cells.count < cols { cells.append((" ", Claude.text, pad)) }
        rows.append(Array(cells.prefix(cols)).map { (text: $0.0, fg: $0.1, bg: $0.2) })
    }

    func plan(atBottom: Bool = true) -> ClaudeDress.Plan {
        var bytes: [UInt8] = []
        var cells: [cadex_terminal_cell] = []
        for row in rows {
            for cell in row {
                let utf8 = Array(cell.text.utf8)
                var c = cadex_terminal_cell()
                c.fg = cell.fg
                c.bg = cell.bg ?? Claude.screen
                c.text_offset = UInt32(bytes.count)
                c.text_len = cell.text == " " ? 0 : UInt16(utf8.count)
                c.flags = cell.bg == nil ? 0 : UInt16(CADEX_CELL_HAS_BACKGROUND)
                bytes += utf8
                cells.append(c)
            }
        }
        return cells.withUnsafeBufferPointer { cellBuffer in
            bytes.withUnsafeBufferPointer { textBuffer in
                ClaudeDress.plan(cells: cellBuffer.baseAddress!, text: textBuffer.baseAddress ?? UnsafePointer(bitPattern: 1)!,
                                 cols: cols, rows: rows.count, palette: Claude.palette, atBottom: atBottom)
            }
        }
    }
}

/// The measured "dark" colors and the Cadex Night terminal.
enum Claude {
    static let text: UInt32 = 0xC9CCD1, screen: UInt32 = 0x121316
    static let palette = ClaudeDress.Palette(TerminalAppearance(
        background: screen, foreground: text, cursor: text, selection: 0x2E3238,
        ansi: [0x2A2D33, 0xF08A8A, 0x6FCF97, 0xF2B65E, 0x8FB8F7, 0xA98BF0, 0x9BC1FF, 0xB5B9C0,
               0x4A4F57, 0xF08A8A, 0x6FCF97, 0xF2B65E, 0x8FB8F7, 0xA98BF0, 0x9BC1FF, 0xEDEEF0]))
}

@MainActor let dressChecks: [(name: String, body: Checks.Body)] = [
    ("Claude's fixed colors take the theme's: the diff by its background, a running tool's dot amber", {
        var s = FakeScreen(cols: 20)
        s.row(("⏺", 0x4EBA65, nil), (" Update", Claude.text, nil))
        s.row(("2 -", 0xDC5A5A, 0x3D0100), ("two", 0xF8F8F2, 0x3D0100))
        s.row(("2 +", 0x50C850, 0x022800), ("TWO", 0xF8F8F2, 0x022800))
        s.row(("⏺", 0x999999, nil), (" Running", Claude.text, nil))
        s.row(("✳ Flambéing…", 0xD77757, nil))
        let plan = s.plan(), p = Claude.palette
        expect(plan.cells[0].fg == p.toolDone, "done dot")
        expect(plan.cells[20].bg == p.deleteBackground && plan.cells[20].fg == p.deleteSign && plan.cells[23].fg == p.deleteText, "removed line")
        expect(plan.cells[40].bg == p.addBackground && plan.cells[40].fg == p.addSign && plan.cells[43].fg == p.addText, "added line")
        expect(plan.cells[60].fg == p.toolRunning, "running dot")
        expect(plan.cells[80].fg == p.live, "the working line in the theme's blue")
        expect(plan.cells[1].fg == Claude.text, "a color Claude did not fix stays")
    }),
    ("a command's short name: variables, env and a leading cd … && go; an agent is its name", {
        expect(TerminalCommand.shortName("PATH=/x /usr/bin/npm run dev") == "npm run dev")
        expect(TerminalCommand.shortName("cd '/Users/d/mind' && env -u CLAUDECODE CLAUDE_CONFIG_DIR=/u/.claude-b claude --resume abc --settings x") == "claude")
        expect(TerminalCommand.shortName("cd /a && cd b && make check") == "make check")
    }),
    ("the mascot is not drawn, the banner's words are", {
        var s = FakeScreen(cols: 40)
        s.row((" ▐▛███▜▌", 0xD77757, nil), ("   Claude Code v2.1.327", Claude.text, nil))
        s.row(("▝▜█████▛▘", 0xD77757, nil), ("  Haiku 5.5", 0x999999, nil))
        s.row(("  ▘▘ ▝▝  ", 0xD77757, nil), ("  /private/tmp", 0x999999, nil))
        s.row(("A plain line ▐ with a block", Claude.text, nil))
        let plan = s.plan()
        expect((0..<3).allSatisfy { r in (0..<9).allSatisfy { plan.hidden[r * 40 + $0] } }, "mascot cells hidden")
        expect(!plan.hidden[12] && !plan.hidden[40 + 11], "the words stay")
        expect(!plan.hidden.suffix(40).contains(true), "a block inside text is not the mascot")
        // /usage's bars start their rows with blocks: not the mascot, not moved.
        var u = FakeScreen(cols: 40)
        u.row(("  Current session", Claude.text, nil))
        u.row(("  ██████▌               12% used", 0x8FB8F7, nil))
        let usage = u.plan()
        expect(!usage.hidden.contains(true) && usage.shift.allSatisfy { $0.dx == 0 }, "a usage bar stays where it is")
        expect((0..<3).allSatisfy { plan.shift[$0].dx == -11 } && plan.shift[3].dx == 0, "the banner's words to the start: \(plan.shift)")
    }),
    ("the input's two rules become one rounded box; one rule alone stays", {
        var s = FakeScreen(cols: 12)
        s.row((String(repeating: "─", count: 12), 0x888888, nil))
        s.row(("❯\u{00A0}hi", Claude.text, nil))
        s.row((String(repeating: "─", count: 12), 0x888888, nil))
        s.row((String(repeating: "─", count: 12), 0xB1B9F9, nil))
        s.row((" Bash command", 0xB1B9F9, nil))
        let plan = s.plan()
        expect(plan.shapes == [ClaudeDress.Shape(top: 0, bottom: 2, left: 0, right: 11, color: Claude.palette.boxFill, outline: false, midRows: true),
                               ClaudeDress.Shape(top: 0, bottom: 2, left: 0, right: 11, color: Claude.palette.boxLine, outline: true, midRows: true)],
               "\(plan.shapes)")
        expect((0..<12).allSatisfy { plan.hidden[$0] && plan.hidden[24 + $0] } && !plan.hidden[12], "rules hidden, input shown")
        expect(!plan.hidden[36], "the permission dialog's rule stays")
    }),
    ("the owner's message is one rounded block in the theme's color", {
        var s = FakeScreen(cols: 10)
        s.row(("❯", 0x999999, 0x373737), (" Read a", 0xFFFFFF, 0x373737))
        s.row(("  more", 0xFFFFFF, 0x373737))
        s.row(("after", Claude.text, nil))
        let plan = s.plan()
        expect(plan.shapes == [ClaudeDress.Shape(top: 0, bottom: 1, left: 0, right: 9, color: Claude.palette.userBackground, outline: false, midRows: false)],
               "\(plan.shapes)")
        expect(plan.cells[2].flags & UInt16(CADEX_CELL_HAS_BACKGROUND) == 0 && plan.cells[2].fg == Claude.palette.strong, "cell backgrounds off, text strong")
    }),
    ("the mode line goes to the status line's right end; other words or history scrolled stay", {
        var s = FakeScreen(cols: 50)
        s.row(("  Haiku 5.5  context 6%", 0x999999, nil))
        s.row(("  ⏵⏵ accept edits on", 0xAF87FF, nil), (" (shift+tab to cycle)", 0x999999, nil))
        let plan = s.plan()
        expect(plan.labels == [ClaudeDress.Label(text: "accept edits", row: 1, col: 37, color: Claude.palette.modeEdits)], "\(plan.labels)")
        expect(plan.shift[0].dy == 1 && plan.shift[1].dy == 0, "the status line down into the mode line's row")
        expect(plan.hidden[50...].allSatisfy { $0 }, "the mode line not drawn")
        expect(s.plan(atBottom: false).labels.isEmpty && !s.plan(atBottom: false).hidden.contains(true), "scrolled up: as Claude drew")
        var boxed = FakeScreen(cols: 50)
        boxed.row(("", Claude.text, nil))
        boxed.row(("                                ◐ medium · /effort", 0x999999, nil))
        boxed.row((String(repeating: "─", count: 50), 0x888888, nil))
        boxed.row(("❯\u{00A0}hi", Claude.text, nil))
        boxed.row((String(repeating: "─", count: 50), 0x888888, nil))
        boxed.row(("  Haiku 5.5", 0x999999, nil))
        boxed.row(("  ⏵⏵ auto mode on", 0xAF87FF, nil), (" (shift+tab to cycle)", 0x999999, nil))
        let moved = boxed.plan()
        expect((1...5).allSatisfy { moved.shift[$0].dy == 1 } && moved.shift[0].dy == 0, "the box and the effort hint go down with it: \(moved.shift)")
        expect(moved.shapes.count == 2 && moved.shapes.allSatisfy { $0.top == 3 && $0.bottom == 5 }, "\(moved.shapes)")
        var shells = FakeScreen(cols: 70)
        shells.row(("  Haiku 5.5  context 6%  macos", 0x999999, nil))
        shells.row(("  ⏵⏵ auto mode on", 0xAF87FF, nil), (" (shift+tab to cycle) · 1 shell · ↓ to manage", 0x999999, nil))
        let withShells = shells.plan().labels
        expect(withShells.count == 2 && withShells[1] == ClaudeDress.Label(text: "1 shell · ↓ to manage", row: 1, col: 32, color: Claude.palette.dim),
               "the background shells right of the folder: \(withShells)")
        var narrow = FakeScreen(cols: 50)
        narrow.row(("  Haiku 5.5  context 6%  macos", 0x999999, nil))
        narrow.row(("  ⏵⏵ auto mode on", 0xAF87FF, nil), (" · 1 shell · ↓ to manage", 0x999999, nil))
        expect(narrow.plan().labels.map(\.text) == ["auto mode"], "no room: the mode alone")
        var wide = FakeScreen(cols: 80)
        wide.row(("  Opus 5.5  context 0%  macos", 0x999999, nil))
        wide.row(("  ⏵⏵ bypass permissions on", 0xAF87FF, nil), (" (shift+tab to cycle) · ← 6 agents", 0x999999, nil))
        wide.row(("                                                          ◐ medium · /effort", 0x999999, nil))
        let w = wide.plan()
        expect(w.labels.map(\.text) == ["bypass permissions", "← 6 agents · ◐ medium"] && w.labels.allSatisfy { $0.row == 1 },
               "the effort hint under the mode line, in a wide pane: \(w.labels)")
        expect(w.hidden[80...].allSatisfy { $0 } && w.shift[0].dy == 1, "the mode and effort rows not drawn, the status line down")
        var lastRule = FakeScreen(cols: 20)
        lastRule.row(("hi", Claude.text, nil))
        lastRule.row((String(repeating: "─", count: 20), 0x888888, nil))
        expect(lastRule.plan().shapes.isEmpty, "a rule on the last row: no box, and no crash")
        var other = FakeScreen(cols: 50)
        other.row(("  status", 0x999999, nil))
        other.row(("  ⏵⏵ accept edits enabled", 0xAF87FF, nil))
        expect(other.plan().labels.isEmpty && !other.plan().hidden.contains(true), "unknown words stay drawn")
    }),
    ("a click on a moved row goes to the cell Claude wrote: the prompt a row up, the banner further right", {
        var boxed = FakeScreen(cols: 50)
        boxed.row(("", Claude.text, nil))
        boxed.row((String(repeating: "─", count: 50), 0x888888, nil))
        boxed.row(("❯\u{00A0}hello world", Claude.text, nil))
        boxed.row((String(repeating: "─", count: 50), 0x888888, nil))
        boxed.row(("  Haiku 5.5", 0x999999, nil))
        boxed.row(("  ⏵⏵ auto mode on", 0xAF87FF, nil), (" (shift+tab to cycle)", 0x999999, nil))
        let shift = boxed.plan().shift
        // The prompt, written on row 2, is drawn on row 3: a click there is a click on row 2.
        expect(ClaudeDress.source(row: 3, col: 8, shift: shift) == (2, 8), "\(ClaudeDress.source(row: 3, col: 8, shift: shift))")
        expect(ClaudeDress.source(row: 0, col: 4, shift: shift) == (0, 4), "a row that did not move")
        let banner = [(dx: -11, dy: 0), (dx: 0, dy: 0)]
        expect(ClaudeDress.source(row: 0, col: 3, shift: banner) == (0, 14), "the banner's words were written 11 columns right")
    }),
]
