import AppKit
import CCadex

/// The typed text as a text box treats it (owner, 2026-11-18): ⌘A selects just it (a second ⌘A
/// the whole terminal), a double click on blank or a triple click selects it, or the paragraph
/// under the pointer outside it, and with it selected Delete clears it and a letter replaces it.
/// Claude Code takes the mouse and cannot delete a selection, so the clearing is done here with
/// its own keys: its cursor put at the text's end by a click, then Backspaces.
extension TerminalView {
    /// ⌘A: the typed text first, then everything.
    public override func selectAll(_ sender: Any?) {
        if mouse.field == nil || session?.hasSelection != true, selectTypedText() { return }
        mouse.field = nil
        session?.selectAll()
        needsDisplay = true
    }

    /// Selects what is typed; false when nothing is (an empty prompt, scrolled into the history).
    func selectTypedText() -> Bool {
        guard let screen = writtenScreen(), let field = inputField(screen), !field.isEmpty else { return false }
        select(from: field.start, to: field.end)
        mouse.field = field
        return true
    }

    /// A double click on blank or a triple click: the typed text when it is under the pointer,
    /// else the paragraph there. False leaves the click to the program or to the core (a word).
    func selectByClicks(at location: CGPoint, clicks: Int) -> Bool {
        guard clicks >= 2, let screen = writtenScreen() else { return false }
        let at = cell(at: location)
        guard (0..<screen.rows).contains(at.row), (0..<screen.cols).contains(at.col),
              clicks >= 3 || screen.isBlank(at.row, at.col) else { return false }
        if let field = inputField(screen), field.rows.contains(at.row) {
            guard !field.isEmpty else { return false }
            select(from: field.start, to: field.end)
            mouse.field = field
            return true
        }
        guard let paragraph = screen.paragraph(row: at.row) else { return false }
        select(from: paragraph.start, to: paragraph.end)
        return true
    }

    /// With the typed text selected: Delete clears it and a letter replaces it (the letter goes
    /// on as typed). True when the key was used up here.
    func replaceSelectedText(_ event: NSEvent) -> Bool {
        guard let field = mouse.field else { return false }
        mouse.field = nil
        guard session?.hasSelection == true else { return false }
        let deleting = event.keyCode == 51 || event.keyCode == 117
        let plain = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        let letter = event.characters?.unicodeScalars.first.map { $0.value >= 0x20 && $0.value != 0x7F && !(0xF700...0xF8FF).contains($0.value) } ?? false
        guard deleting || (plain && letter) else { return false }
        clear(field)
        session?.clearSelection()
        needsDisplay = true
        return deleting
    }

    /// The program's own keys for clearing its text: the shell's Ctrl+E Ctrl+U (zsh's whole line,
    /// bash's to its start from the end); Claude's click after the text, Ctrl+E, then Backspaces.
    private func clear(_ field: InputField) {
        guard let session, let screen = writtenScreen() else { return }
        switch field.kind {
        case .shell:
            session.write([0x05, 0x15])
        case .claude:
            let after = point(InputField.Cell(row: field.end.row, col: min(field.end.col + 1, screen.cols - 1)), 0.5)
            for action in [CADEX_MOUSE_PRESS, CADEX_MOUSE_RELEASE] {
                session.mouse(geometry.mouseEvent(at: after, action: action, button: CADEX_MOUSE_BUTTON_LEFT, mods: 0))
            }
            session.key(UInt16(CADEX_KEY_NONE), mods: UInt8(CADEX_MOD_CTRL), text: "e", unshifted: 0x65)
            for _ in 0..<screen.eraseCount(field) { session.key(UInt16(CADEX_KEY_BACKSPACE), mods: 0) }
        }
    }

    /// Claude's input box when there is one, else the shell's typed line.
    private func inputField(_ screen: WrittenScreen) -> InputField? {
        screen.claudeInput() ?? screen.shellInput(cursorRow: cursorRow)
    }

    /// The screen as written; nil while the view shows the history above it.
    func writtenScreen() -> WrittenScreen? {
        guard let frame = session?.currentFrame()?.pointee, let cells = frame.cells, let text = frame.text, frame.rows > 0,
              frame.scroll_offset + UInt32(frame.rows) >= frame.scroll_total else { return nil }
        let count = Int(frame.cols) * Int(frame.rows)
        let buffer = UnsafeBufferPointer(start: cells, count: count)
        return WrittenScreen(cols: Int(frame.cols), rows: Int(frame.rows),
                             text: buffer.map { String(decoding: UnsafeBufferPointer(start: text + Int($0.text_offset), count: Int($0.text_len)), as: UTF8.self) },
                             flags: buffer.map(\.flags))
    }

    /// The written cell at a point already moved to the written place (`written`).
    private func cell(at location: CGPoint) -> InputField.Cell {
        let g = geometry
        let width = CGFloat(g.cellWidth) / g.scale, height = CGFloat(g.cellHeight) / g.scale
        return .init(row: Int(((g.viewSize.height - location.y - g.padding) / height).rounded(.down)),
                     col: Int(((location.x - g.padding) / width).rounded(.down)))
    }

    /// A point inside a written cell, `fraction` of the way across it.
    private func point(_ cell: InputField.Cell, _ fraction: CGFloat) -> CGPoint {
        let g = geometry
        let width = CGFloat(g.cellWidth) / g.scale, height = CGFloat(g.cellHeight) / g.scale
        return CGPoint(x: g.padding + (CGFloat(cell.col) + fraction) * width,
                       y: g.viewSize.height - g.padding - (CGFloat(cell.row) + 0.5) * height)
    }

    /// The core's selection from one cell to another, both included.
    private func select(from start: InputField.Cell, to end: InputField.Cell) {
        guard let session else { return }
        let first = geometry.pointer(at: point(start, 0.1)), last = geometry.pointer(at: point(end, 0.9))
        session.selectPress(first, clicks: 1, extend: false)
        _ = session.selectDrag(last)
        session.selectRelease(last)
        needsDisplay = true
    }
}
