import CCadex
import CoreGraphics

/// Converts between the view's points and the terminal's cells. Pure, so
/// the padding and Retina scale rules are testable without a window.
struct TerminalGeometry {
    /// View size in points.
    var viewSize: CGSize
    /// Backing scale: 2 on Retina.
    var scale: CGFloat
    /// Space between the view edge and the text, in points.
    var padding: CGFloat
    /// Cell size in pixels.
    var cellWidth: Int
    var cellHeight: Int
    var cols: Int
    var rows: Int

    /// The pointer for a location in view points, with y going up from the
    /// bottom as AppKit reports it. Outside the grid, the cell is clamped to
    /// the nearest one, so dragging past the edge still selects to it.
    func pointer(at location: CGPoint) -> cadex_terminal_pointer {
        let x = location.x * scale
        let y = (viewSize.height - location.y) * scale
        let pad = padding * scale
        let col = Int(((x - pad) / CGFloat(max(cellWidth, 1))).rounded(.down))
        let row = Int(((y - pad) / CGFloat(max(cellHeight, 1))).rounded(.down))
        return cadex_terminal_pointer(
            x: Double(x),
            y: Double(y),
            col: UInt16(clamping: min(max(col, 0), max(cols - 1, 0))),
            row: UInt16(clamping: min(max(row, 0), max(rows - 1, 0))),
            cell_width: UInt16(clamping: cellWidth),
            padding_left: UInt16(clamping: Int(pad.rounded())),
            view_height: UInt32(clamping: Int((viewSize.height * scale).rounded())))
    }
}

/// Turns scroll wheel and trackpad deltas into whole rows, keeping the
/// remainder so slow trackpad scrolling still moves.
struct ScrollAccumulator {
    private var pending: CGFloat = 0

    /// deltaY as NSEvent.scrollingDeltaY reports it: positive moves the
    /// content down, toward older lines. precise: trackpad (points) versus
    /// a mouse wheel (lines). Returns rows to scroll, negative going up.
    mutating func rows(deltaY: CGFloat, precise: Bool, cellHeightPoints: CGFloat) -> Int32 {
        let lines = precise ? deltaY / max(cellHeightPoints, 1) : deltaY
        pending -= lines
        let whole = pending.rounded(.towardZero)
        pending -= whole
        return Int32(clamping: Int(whole))
    }

    mutating func reset() {
        pending = 0
    }
}
