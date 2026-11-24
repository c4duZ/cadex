import CCadex
import Checks
@testable import Terminal

/// ClaudeFootPin: Claude's input box and status line stay at the pane's foot while the history
/// scrolls (the owner, 2026-11-24), from the screen's bottom the core captures with each frame.
@MainActor let footPinChecks: [(name: String, body: Checks.Body)] = [
    ("the bottom's box and status line go over the history's last rows, live; the cursor with them", {
        var history = FakeScreen(cols: 20)
        for i in 0..<8 { history.row(("old \(i)", Claude.text, nil)) }
        var bottom = FakeScreen(cols: 20)
        for i in 0..<3 { bottom.row(("answer \(i)", Claude.text, nil)) }
        bottom.row((String(repeating: "─", count: 20), 0x888888, nil))
        bottom.row(("❯\u{00A0}typing", Claude.text, nil))
        bottom.row((String(repeating: "─", count: 20), 0x888888, nil))
        bottom.row(("  Opus 5.5", 0x999999, nil))
        bottom.row(("  ⏵⏵ auto mode on", 0xAF87FF, nil), (" (shift+tab to cycle)", 0x999999, nil))
        let pin = history.withFrame(scrolled: true) { view in
            bottom.withFrame(cursorRow: 4) { ClaudeFootPin.compose(view: view, bottom: $0, palette: Claude.palette) }
        }
        guard let pin else { return expect(false, "no pin") }
        expect(pin.from == 3, "the foot from the box's top rule: \(pin.from)")
        let lines = pin.with { f in (0..<8).map { r in (0..<20).map { c -> String in
            let cell = f.cells![r * 20 + c]
            return cell.text_len == 0 ? " " : String(decoding: UnsafeBufferPointer(start: f.text! + Int(cell.text_offset), count: Int(cell.text_len)), as: UTF8.self)
        }.joined() } }
        expect(lines[0].hasPrefix("old 0") && lines[2].hasPrefix("old 2"), "the history above: \(lines)")
        expect(lines[4].hasPrefix("❯\u{00A0}typing") && lines[6].hasPrefix("  Opus 5.5"), "the foot below: \(lines)")
        expect(pin.frame.cursor_visible && pin.frame.cursor_y == 4, "the cursor in the box")
        let plan = pin.with { f in ClaudeDress.plan(cells: f.cells!, text: f.text!, cols: 20, rows: 8, palette: Claude.palette) }
        expect(plan.shapes.contains { $0.outline && $0.top == 4 && $0.bottom == 6 }, "the box dressed, down into the mode row: \(plan.shapes)")
    }),
    ("no box at the bottom (a dialog, the / menu), or a foot as tall as the pane: nothing pinned", {
        var history = FakeScreen(cols: 20)
        for i in 0..<6 { history.row(("old \(i)", Claude.text, nil)) }
        var dialog = FakeScreen(cols: 20)
        for i in 0..<6 { dialog.row(("choice \(i)", Claude.text, nil)) }
        let none = history.withFrame(scrolled: true) { view in
            dialog.withFrame { ClaudeFootPin.compose(view: view, bottom: $0, palette: Claude.palette) }
        }
        expect(none == nil, "a dialog: as Claude drew it")
        var tall = FakeScreen(cols: 20)
        tall.row((String(repeating: "─", count: 20), 0x888888, nil))
        for _ in 0..<3 { tall.row(("❯\u{00A0}long", Claude.text, nil)) }
        tall.row((String(repeating: "─", count: 20), 0x888888, nil))
        tall.row(("  Opus 5.5", 0x999999, nil))
        let big = history.withFrame(scrolled: true) { view in
            tall.withFrame { ClaudeFootPin.compose(view: view, bottom: $0, palette: Claude.palette) }
        }
        expect(big == nil, "a foot as tall as the pane hides the history: not pinned")
    }),
]
