import CCadex
import simd

/// Turns a frame into quads, in painting order: cell backgrounds, selection,
/// block cursor, glyphs, underline and strikethrough, thin cursors and the
/// scrollbar on top.
/// Pure apart from the atlas lookups, so the layout rules are testable.
struct QuadBuilder {
    private var quads: [QuadInstance] = []

    /// Selection tint over the cells: the text color at low opacity, so it
    /// reads on any theme. Picked by eye against the default dark theme.
    static let selectionAlpha: Float = 0.3
    /// Scrollbar: thin, inside the right padding, shown only while the view
    /// is not at the bottom of the history.
    static let scrollbarWidthPoints: Float = 3
    static let scrollbarAlpha: Float = 0.35

    mutating func build(frame: cadex_terminal_frame, atlas: GlyphAtlas, metrics m: CellMetrics,
                        padding: SIMD2<Float>, viewSize: SIMD2<Float>) -> [QuadInstance] {
        quads.removeAll(keepingCapacity: true)
        let cols = Int(frame.cols)
        let rows = Int(frame.rows)
        guard cols > 0, rows > 0, let cells = frame.cells else { return quads }
        let cellW = Float(m.width)
        let cellH = Float(m.height)
        let cursorAt = frame.cursor_visible ? Int(frame.cursor_y) * cols + Int(frame.cursor_x) : -1
        let cursorColor = rgba(frame.has_cursor_color ? frame.cursor_color : frame.foreground)
        let blockCursor = frame.cursor_style == UInt8(CADEX_CURSOR_BLOCK)

        func origin(_ index: Int) -> SIMD2<Float> {
            SIMD2(padding.x + Float(index % cols) * cellW, padding.y + Float(index / cols) * cellH)
        }

        for index in 0..<(cols * rows) where cells[index].flags & UInt16(CADEX_CELL_HAS_BACKGROUND) != 0 {
            solid(origin(index), SIMD2(cellW, cellH), rgba(cells[index].bg))
        }
        let selectionColor = rgba(frame.foreground, alpha: Self.selectionAlpha)
        for index in 0..<(cols * rows) where cells[index].flags & UInt16(CADEX_CELL_SELECTED) != 0 {
            solid(origin(index), SIMD2(cellW, cellH), selectionColor)
        }
        if cursorAt >= 0, blockCursor {
            solid(origin(cursorAt), SIMD2(cellW, cellH), cursorColor)
        }

        for index in 0..<(cols * rows) {
            let cell = cells[index]
            if cell.text_len == 0 || cell.flags & UInt16(CADEX_CELL_SPACER) != 0 { continue }
            // The glyph under a block cursor takes the background color to stay readable.
            let fgRGB = (index == cursorAt && blockCursor) ? frame.background : cell.fg
            let faint = cell.flags & UInt16(CADEX_CELL_FAINT) != 0
            glyph(cell, frame: frame, at: origin(index), color: rgba(fgRGB, alpha: faint ? 0.5 : 1), atlas: atlas, metrics: m)
        }

        for index in 0..<(cols * rows) {
            decorations(cells[index], at: origin(index), metrics: m)
        }

        if cursorAt >= 0, !blockCursor {
            cursor(style: frame.cursor_style, at: origin(cursorAt), color: cursorColor, metrics: m)
        }
        scrollbar(frame, metrics: m, padding: padding, viewSize: viewSize)
        return quads
    }

    private mutating func glyph(_ cell: cadex_terminal_cell, frame: cadex_terminal_frame, at origin: SIMD2<Float>,
                                color: SIMD4<Float>, atlas: GlyphAtlas, metrics m: CellMetrics) {
        guard let textBase = frame.text else { return }
        let bytes = UnsafeBufferPointer(start: textBase + Int(cell.text_offset), count: Int(cell.text_len))
        let text = String(decoding: bytes, as: UTF8.self)
        let wide = cell.flags & UInt16(CADEX_CELL_WIDE) != 0
        guard let g = atlas.glyph(
            text: text,
            bold: cell.flags & UInt16(CADEX_CELL_BOLD) != 0,
            italic: cell.flags & UInt16(CADEX_CELL_ITALIC) != 0,
            cells: wide ? 2 : 1)
        else { return }

        let size = Float(GlyphAtlas.size)
        let uv = SIMD4(Float(g.x) / size, Float(g.y) / size, Float(g.x + g.width) / size, Float(g.y + g.height) / size)
        let topLeft = origin - SIMD2(Float(atlas.padX), Float(atlas.padY))
        quads.append(QuadInstance(
            origin: topLeft, size: SIMD2(Float(g.width), Float(g.height)), uv: uv, color: color,
            kind: g.isColor ? QuadInstance.colorGlyph : QuadInstance.maskGlyph))
    }

    private mutating func decorations(_ cell: cadex_terminal_cell, at origin: SIMD2<Float>, metrics m: CellMetrics) {
        let width = Float(m.width) * (cell.flags & UInt16(CADEX_CELL_WIDE) != 0 ? 2 : 1)
        let thickness = Float(m.lineThickness)
        let color = rgba(cell.fg)
        let underline = (cell.flags >> UInt16(CADEX_CELL_UNDERLINE_SHIFT)) & 0b111
        if underline != 0 {
            let y = origin.y + Float(m.baseline + m.underlineOffset)
            solid(SIMD2(origin.x, y), SIMD2(width, thickness), color)
            if underline == 2 {  // double
                solid(SIMD2(origin.x, y + thickness * 2), SIMD2(width, thickness), color)
            }
        }
        if cell.flags & UInt16(CADEX_CELL_STRIKETHROUGH) != 0 {
            let y = origin.y + Float(m.baseline) - Float(m.height) * 0.3
            solid(SIMD2(origin.x, y), SIMD2(width, thickness), color)
        }
    }

    private mutating func cursor(style: UInt8, at origin: SIMD2<Float>, color: SIMD4<Float>, metrics m: CellMetrics) {
        let w = Float(m.width)
        let h = Float(m.height)
        let line = max(1, (1.5 * Float(m.scale)).rounded())
        switch Int32(style) {
        case CADEX_CURSOR_BAR:
            solid(origin, SIMD2(line, h), color)
        case CADEX_CURSOR_UNDERLINE:
            solid(SIMD2(origin.x, origin.y + h - line), SIMD2(w, line), color)
        default:  // hollow block
            solid(origin, SIMD2(w, line), color)
            solid(SIMD2(origin.x, origin.y + h - line), SIMD2(w, line), color)
            solid(origin, SIMD2(line, h), color)
            solid(SIMD2(origin.x + w - line, origin.y), SIMD2(line, h), color)
        }
    }

    private mutating func scrollbar(_ frame: cadex_terminal_frame, metrics m: CellMetrics,
                                    padding: SIMD2<Float>, viewSize: SIMD2<Float>) {
        let total = Float(frame.scroll_total)
        let shown = Float(frame.rows)
        let offset = Float(frame.scroll_offset)
        guard total > shown, offset + shown < total else { return }
        let width = Self.scrollbarWidthPoints * Float(m.scale)
        let trackTop = padding.y
        let trackHeight = viewSize.y - padding.y * 2
        let height = max(width * 2, trackHeight * shown / total)
        let y = trackTop + (trackHeight - height) * offset / max(total - shown, 1)
        let x = viewSize.x - (padding.x + width) / 2
        solid(SIMD2(x, y), SIMD2(width, height), rgba(frame.foreground, alpha: Self.scrollbarAlpha))
    }

    private mutating func solid(_ origin: SIMD2<Float>, _ size: SIMD2<Float>, _ color: SIMD4<Float>) {
        quads.append(QuadInstance(origin: origin, size: size, uv: .zero, color: color, kind: QuadInstance.solid))
    }
}
