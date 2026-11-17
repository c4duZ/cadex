import AppKit
import UILooks

/// The terminal's scrollbar as the Pane mockup draws it (plan 28 phase D; components.pane.scrollbar):
/// a column of 8 pt at the box's right edge, a mark at each message the owner sent to the agent
/// (amber where the agent asked for something) and the thumb where the view is. A click or a drag
/// moves the view there. It replaces the thin bar the Metal frame drew only while scrolled.
/// The pane layout places it (tabs); the terminal feeds it each frame and each mark.
@MainActor
public final class TerminalScrollbar: NSView {
    typealias S = DesignTokens.Pane.Scrollbar

    struct Mark: Equatable {
        /// The row in the whole history (scrollback and screen), from the top.
        var row: Int
        var needs: Bool
    }

    weak var terminal: TerminalView?
    private(set) var total = 0
    private(set) var offset = 0
    private(set) var rows = 0
    private(set) var marks: [Mark] = []
    /// A long session keeps its last marks: past this, the oldest go.
    static let maxMarks = 400

    public override var isFlipped: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }

    /// The history's size and where the view is, from each frame; redrawn only when they change.
    func update(total: Int, offset: Int, rows: Int) {
        guard total != self.total || offset != self.offset || rows != self.rows else { return }
        // A shorter history: the screen was cleared (or /clear); marks past its end go.
        if total < self.total { marks.removeAll { $0.row >= total } }
        self.total = total
        self.offset = offset
        self.rows = rows
        needsDisplay = true
    }

    /// A mark on the cursor's row: the owner sent a message (`needs` false) or the agent asked
    /// for something (true). One per row; the amber wins.
    func mark(cursorRow: Int, needs: Bool) {
        guard rows > 0 else { return }
        let row = max(total - rows, 0) + cursorRow
        if let index = marks.firstIndex(where: { $0.row == row }) {
            marks[index].needs = marks[index].needs || needs
        } else {
            marks.append(Mark(row: row, needs: needs))
            if marks.count > Self.maxMarks { marks.removeFirst(marks.count - Self.maxMarks) }
        }
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        S.bg.setFill()
        bounds.fill()
        S.borderLeft.setFill()
        NSRect(x: 0, y: 0, width: DesignTokens.Stroke.hairline, height: bounds.height).fill()
        guard total > 0 else { return }
        let height = bounds.height
        for mark in marks {
            let size = NSSize(width: UILooks.pt(S.Mark.width), height: UILooks.pt(S.Mark.height))
            let y = min(max(height * CGFloat(mark.row) / CGFloat(total), 0), height - size.height)
            let rect = NSRect(x: (bounds.width - size.width) / 2, y: y, width: size.width, height: size.height)
            (mark.needs ? S.Mark.needs : S.Mark.color).setFill()
            NSBezierPath(roundedRect: rect, xRadius: UILooks.pt(S.Mark.radius) / 2, yRadius: UILooks.pt(S.Mark.radius) / 2).fill()
        }
        guard total > rows, let thumb = thumbRect() else { return }
        S.Thumb.color.setFill()
        let radius = UILooks.pt(S.Thumb.radius)
        NSBezierPath(roundedRect: thumb, xRadius: radius, yRadius: radius).fill()
    }

    /// Where the view is in the history.
    func thumbRect() -> NSRect? {
        guard total > rows, rows > 0 else { return nil }
        let width = UILooks.pt(S.Thumb.width)
        let length = max(bounds.height * CGFloat(rows) / CGFloat(total), width * 2)
        let y = (bounds.height - length) * CGFloat(offset) / CGFloat(max(total - rows, 1))
        return NSRect(x: (bounds.width - width) / 2, y: y, width: width, height: length)
    }

    public override func mouseDown(with event: NSEvent) { jump(to: event) }
    public override func mouseDragged(with event: NSEvent) { jump(to: event) }

    /// The view centered on the row under the pointer.
    private func jump(to event: NSEvent) {
        guard total > rows, bounds.height > 0 else { return }
        let y = convert(event.locationInWindow, from: nil).y
        let target = Int(CGFloat(total) * y / bounds.height) - rows / 2
        let wanted = min(max(target, 0), total - rows)
        terminal?.scrollHistory(by: wanted - offset)
    }
}

extension TerminalView {
    /// Moves the view through the history by rows (negative goes up): the scrollbar's click.
    func scrollHistory(by rows: Int) {
        guard rows != 0 else { return }
        session?.scroll(rows: Int32(rows))
        needsDisplay = true
    }
}
