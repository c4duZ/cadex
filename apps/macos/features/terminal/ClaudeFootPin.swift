import CCadex

/// Claude's foot (its input box and the status line under it) kept at the pane's bottom while the
/// owner scrolls the history, as in Claude's own fullscreen mode, which Cadex turns off to keep the
/// conversation in the terminal's history (CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN, session-kit). The
/// owner, 2026-11-24: "a nossa caixa de escrita tá sumindo quando a gente sobe um pouco o terminal".
/// Live, not a copy: the core captures the screen's bottom with every frame while the view is
/// scrolled (cadex_terminal_bottom_frame), and the history rows over the foot are not drawn.
struct ClaudeFootPin {
    var cells: [cadex_terminal_cell]
    var text: [UInt8]
    /// The frame's fields with the foot's cursor; its pointers are set where it is drawn (`with`).
    var frame: cadex_terminal_frame
    /// The composite's row where the foot starts.
    var from: Int

    /// The view's rows with the bottom's foot over their last ones, or nil when the bottom has no
    /// box (a dialog, the / menu: as Claude drew it), the foot leaves under two rows of history, or
    /// the frames do not match.
    static func compose(view: cadex_terminal_frame, bottom: cadex_terminal_frame, palette: ClaudeDress.Palette) -> ClaudeFootPin? {
        let cols = Int(view.cols), rows = Int(view.rows)
        guard cols > 0, rows > 2, bottom.cols == view.cols, bottom.rows == view.rows,
              let viewCells = view.cells, let viewText = view.text, let bottomCells = bottom.cells, let bottomText = bottom.text,
              let top = ClaudeDress.plan(cells: bottomCells, text: bottomText, cols: cols, rows: rows, palette: palette).footTop,
              top >= 2 else { return nil }
        let count = cols * rows
        var cells = Array(UnsafeBufferPointer(start: viewCells, count: top * cols))
        let offset = view.text_len
        let stale = UInt16(CADEX_CELL_SELECTED | CADEX_CELL_MATCH | CADEX_CELL_MATCH_CURRENT)
        for i in (top * cols)..<count {
            var cell = bottomCells[i]
            cell.text_offset += offset
            cell.flags &= ~stale
            cells.append(cell)
        }
        let text = Array(UnsafeBufferPointer(start: viewText, count: Int(view.text_len)))
            + Array(UnsafeBufferPointer(start: bottomText, count: Int(bottom.text_len)))
        var frame = view
        frame.text_len = UInt32(text.count)
        // Claude's cursor is in its box: drawn where the box is, or not at all.
        frame.cursor_visible = bottom.cursor_visible && Int(bottom.cursor_y) >= top
        frame.cursor_x = bottom.cursor_x
        frame.cursor_y = bottom.cursor_y
        frame.cursor_style = bottom.cursor_style
        return ClaudeFootPin(cells: cells, text: text, frame: frame, from: top)
    }

    /// The composite as a frame for `body`, its pointers valid only inside it.
    func with<R>(_ body: (cadex_terminal_frame) -> R) -> R {
        cells.withUnsafeBufferPointer { c in
            text.withUnsafeBufferPointer { t in
                var frame = self.frame
                frame.cells = c.baseAddress
                frame.text = t.baseAddress
                return body(frame)
            }
        }
    }
}
