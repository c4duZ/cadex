import CCadex

/// What the user is typing, in the cells as the program wrote them (owner, 2026-11-18: ⌘A, the
/// triple click and Delete take just that, as in any text box): Claude Code's input box, or the
/// shell's line after its prompt (the cells the core marks CADEX_CELL_INPUT, from OSC 133 B).
struct InputField: Equatable {
    enum Kind { case claude, shell }
    struct Cell: Equatable {
        var row: Int
        var col: Int
    }

    var kind: Kind
    /// The rows the field takes, the empty ones of a box included.
    var rows: ClosedRange<Int>
    /// The first cell of the text and the last one with text; `end` before `start` when empty.
    var start: Cell
    var end: Cell

    var isEmpty: Bool { end.row < start.row || (end.row == start.row && end.col < start.col) }
}

/// The screen as text and flags, cell by cell, and what is found on it. Pure, for the tests.
struct WrittenScreen {
    var cols: Int
    var rows: Int
    var text: [String]
    var flags: [UInt16]

    func cell(_ row: Int, _ col: Int) -> String { text[row * cols + col] }

    /// No text: empty, a space or Claude's no-break space after its "❯".
    func isBlank(_ row: Int, _ col: Int) -> Bool {
        let t = cell(row, col)
        return t.isEmpty || t == " " || t == "\u{00A0}"
    }

    /// A whole row of "─": the rules around Claude's input.
    func isRule(_ row: Int) -> Bool { (0..<cols).allSatisfy { cell(row, $0) == "─" } }

    func isBlankRow(_ row: Int) -> Bool { isRule(row) || (0..<cols).allSatisfy { isBlank(row, $0) } }

    /// The last cell with text in the rows, from the bottom; nil when they are all blank.
    func lastText(in rows: ClosedRange<Int>, from col: Int = 0) -> InputField.Cell? {
        for row in rows.reversed() {
            if let c = (0..<cols).last(where: { !isBlank(row, $0) }), row != rows.lowerBound || c >= col {
                return .init(row: row, col: c)
            }
        }
        return nil
    }

    /// Claude Code's input: the last box on screen, a rule, rows starting with "❯", a rule. The
    /// text starts after "❯ " and its continuation rows are indented as far.
    func claudeInput() -> InputField? {
        var found: InputField?
        var r = 0
        while r + 2 < rows {
            guard isRule(r), cell(r + 1, 0) == "❯", let bottom = (r + 2..<min(rows, r + 60)).first(where: isRule) else { r += 1; continue }
            let inside = (r + 1)...(bottom - 1)
            let start = InputField.Cell(row: r + 1, col: min(2, cols - 1))
            found = InputField(kind: .claude, rows: inside, start: start,
                               end: lastText(in: inside, from: start.col) ?? .init(row: start.row, col: start.col - 1))
            r = bottom + 1
        }
        return found
    }

    /// The shell's input: the marked cells on the cursor's row, and the rows above while the row
    /// starts typed (a long line wrapped); a row that starts with the prompt is where it began (the
    /// command before is marked too). Nil when nothing is typed.
    func shellInput(cursorRow: Int) -> InputField? {
        func isInput(_ row: Int, _ col: Int) -> Bool { flags[row * cols + col] & UInt16(CADEX_CELL_INPUT) != 0 }
        func hasInput(_ row: Int) -> Bool { (0..<cols).contains { isInput(row, $0) } }
        guard (0..<rows).contains(cursorRow), hasInput(cursorRow) else { return nil }
        var top = cursorRow
        while top > 0, isInput(top, 0), hasInput(top - 1) { top -= 1 }
        guard let first = (0..<cols).first(where: { isInput(top, $0) }) else { return nil }
        let start = InputField.Cell(row: top, col: first)
        return InputField(kind: .shell, rows: top...cursorRow, start: start,
                          end: lastText(in: top...cursorRow, from: first) ?? .init(row: top, col: first - 1))
    }

    /// The paragraph around a row: the rows with text above and below it, up to a blank row or a
    /// rule. Nil on a blank row.
    func paragraph(row: Int) -> (start: InputField.Cell, end: InputField.Cell)? {
        guard (0..<rows).contains(row), !isBlankRow(row) else { return nil }
        var top = row, bottom = row
        while top > 0, !isBlankRow(top - 1) { top -= 1 }
        while bottom + 1 < rows, !isBlankRow(bottom + 1) { bottom += 1 }
        guard let first = (0..<cols).first(where: { !isBlank(top, $0) }), let last = lastText(in: bottom...bottom) else { return nil }
        return (.init(row: top, col: first), last)
    }

    /// At most how many Backspaces clear the field's text: one per cell with text, one per row
    /// break. More than needed does nothing at the text's start.
    func eraseCount(_ field: InputField) -> Int {
        guard !field.isEmpty else { return 0 }
        var count = 0
        for row in field.start.row...field.end.row {
            let from = row == field.start.row ? field.start.col : 0
            let to = row == field.end.row ? field.end.col : cols - 1
            if from <= to { count += (from...to).filter { !cell(row, $0).isEmpty }.count }
        }
        return count + field.end.row - field.start.row
    }
}
