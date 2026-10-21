import CCadex

/// Ligatures (plan 15, phase C): with the font's "calt" or "liga" on, a run
/// of symbols the font joins ("->", "!=", "===") is drawn as one glyph over
/// its cells instead of letter by letter.
extension QuadBuilder {
    struct SymbolRun {
        var text: String
        var count: Int
        var bold: Bool
        var italic: Bool
    }

    /// The symbols programming fonts join; letters and digits never start a run.
    static let joinable = Set("!#$%&*+-./:;<=>?@\\^_|~".utf8)
    /// Longer runs are rare and would fill the atlas with one-off glyphs.
    static let longestRun = 8

    /// Two or more cells from `start` on the same row, each one joinable
    /// symbol in the same color and style, none under the cursor.
    func symbolRun(_ cells: UnsafePointer<cadex_terminal_cell>, from start: Int, cols: Int,
                   frame: cadex_terminal_frame, cursorAt: Int) -> SymbolRun? {
        guard let textBase = frame.text else { return nil }
        let styleFlags = UInt16(CADEX_CELL_BOLD | CADEX_CELL_ITALIC | CADEX_CELL_FAINT | CADEX_CELL_WIDE)
        let first = cells[start]
        let rowEnd = (start / cols + 1) * cols
        var bytes: [UInt8] = []
        var index = start
        while index < rowEnd, bytes.count < Self.longestRun, index != cursorAt {
            let cell = cells[index]
            guard cell.text_len == 1, cell.fg == first.fg, cell.flags & styleFlags == first.flags & styleFlags,
                  cell.flags & UInt16(CADEX_CELL_WIDE) == 0 else { break }
            let byte = textBase[Int(cell.text_offset)]
            guard Self.joinable.contains(byte) else { break }
            bytes.append(byte)
            index += 1
        }
        guard bytes.count >= 2 else { return nil }
        return SymbolRun(text: String(decoding: bytes, as: UTF8.self), count: bytes.count,
                         bold: first.flags & UInt16(CADEX_CELL_BOLD) != 0, italic: first.flags & UInt16(CADEX_CELL_ITALIC) != 0)
    }
}
