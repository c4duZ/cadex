import AppKit
import Editor

/// The review's files stacked in one view (docs/spec/review.md): only the
/// rows on screen are drawn, so 5 thousand lines in 50 files scroll like
/// a short file (the subagent's conversation went from a view per entry to
/// one view for the same reason: 25 MB less, plan 17). Rows have the
/// editor's font and colors; a wrapped line takes the rows it needs.
/// Clicking a line's numbers marks it (⇧ extends), ↑ ↓ move the cursor.
@MainActor
final class ReviewTextView: NSView {
    private(set) var layout = ReviewLayout(files: [], options: .init(), notes: { _ in nil })
    private(set) var files: [ReviewFileDiff] = []
    var wrap = false { didSet { if wrap != oldValue { relayout() } } }
    var showWhitespace = false { didSet { needsDisplay = true } }
    /// The row the keyboard is on, and the other end of the marked run.
    private(set) var cursor = 0
    private var anchor = 0
    /// "Show more" on a fold: the document opens it.
    var onOpenFold: ((Int, Int) -> Void)?
    /// The cursor moved (the tree follows the file).
    var onCursor: ((Int) -> Void)?

    let look = EditorAppearance.current
    lazy var charWidth: CGFloat = ("M" as NSString).size(withAttributes: [.font: look.font]).width
    lazy var lineHeight: CGFloat = ceil(look.font.ascender - look.font.descender + look.font.leading) + 3
    var headerHeight: CGFloat { lineHeight + 14 }
    /// Each row's top; one more at the end for the total height.
    private(set) var tops: [CGFloat] = [0]
    var colored: [String: (NSAttributedString, [NSRange])] = [:]

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// New rows (a new read, a fold opened): the cursor stays on the same
    /// line when it is still there.
    func show(_ layout: ReviewLayout, files: [ReviewFileDiff]) {
        let keep = layout.rows.isEmpty ? nil : rowKey(cursor)
        if files.count != self.files.count || zip(files, self.files).contains(where: { $0.patch != $1.patch }) { colored = [:] }
        self.layout = layout
        self.files = files
        if let keep, let same = layout.rows.firstIndex(where: { rowKey(for: $0) == keep }) { cursor = same } else { cursor = min(cursor, max(layout.rows.count - 1, 0)) }
        anchor = cursor
        relayout()
    }

    // MARK: Geometry

    var gutterWidth: CGFloat {
        let biggest = files.map { max($0.before.count, $0.after.count) }.max() ?? 1
        let digits = CGFloat(max(String(biggest).count, 3))
        return 2 * (digits * charWidth + 10) + charWidth + 10
    }

    /// Columns of text a row holds before wrapping.
    var columns: Int { max(Int((bounds.width - gutterWidth - 16) / charWidth), 20) }

    func height(of row: ReviewLayout.Row) -> CGFloat {
        switch row {
        case .header: return headerHeight
        case .line where wrap:
            let length = ReviewLayout.text(of: row, in: files).replacingOccurrences(of: "\t", with: "    ").count
            return lineHeight * CGFloat(max(1, (length + columns - 1) / columns))
        default: return lineHeight
        }
    }

    func relayout() {
        var y: CGFloat = 0
        tops = [0]
        tops.reserveCapacity(layout.rows.count + 1)
        for row in layout.rows {
            y += height(of: row)
            tops.append(y)
        }
        let height = max(y + 40, enclosingScrollView?.contentSize.height ?? 0)
        setFrameSize(NSSize(width: enclosingScrollView?.contentSize.width ?? bounds.width, height: height))
        needsDisplay = true
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        if wrap { relayout() }
    }

    /// The row at a height (binary search over the tops).
    func row(at y: CGFloat) -> Int? {
        guard !layout.rows.isEmpty, y >= 0, y < tops[tops.count - 1] else { return nil }
        var low = 0
        var high = layout.rows.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if tops[mid] <= y { low = mid } else { high = mid - 1 }
        }
        return low
    }

    func rect(of index: Int) -> NSRect {
        NSRect(x: 0, y: tops[index], width: bounds.width, height: tops[index + 1] - tops[index])
    }

    /// Scrolls so `index` shows near the top, and puts the cursor there.
    func go(to index: Int) {
        guard layout.rows.indices.contains(index) else { return }
        cursor = index
        anchor = index
        let target = rect(of: index)
        scroll(NSPoint(x: 0, y: max(target.minY - lineHeight * 2, 0)))
        needsDisplay = true
        onCursor?(index)
    }

    // MARK: Marking

    /// The marked rows, in order (the cursor's alone when nothing else is).
    var marked: [Int] { Array(min(cursor, anchor)...max(cursor, anchor)).filter { layout.rows.indices.contains($0) } }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let index = row(at: point.y) else { return }
        if case .fold(let file, let region, _) = layout.rows[index] { return onOpenFold?(file, region) ?? () }
        move(to: index, extending: event.modifierFlags.contains(.shift))
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = row(at: point.y) { move(to: index, extending: true) }
        autoscroll(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let extend = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 126: move(to: max(cursor - 1, 0), extending: extend)
        case 125: move(to: min(cursor + 1, layout.rows.count - 1), extending: extend)
        default: super.keyDown(with: event)
        }
    }

    private func move(to index: Int, extending: Bool) {
        guard layout.rows.indices.contains(index) else { return }
        cursor = index
        if !extending { anchor = index }
        scrollToVisible(rect(of: index))
        needsDisplay = true
        onCursor?(index)
    }

    // MARK: Keys that survive a new read

    private func rowKey(_ index: Int) -> String? {
        layout.rows.indices.contains(index) ? rowKey(for: layout.rows[index]) : nil
    }

    private func rowKey(for row: ReviewLayout.Row) -> String {
        switch row {
        case .header(let file): "h\(files.indices.contains(file) ? files[file].file.path : "")"
        case .line(let file, let kind, let old, let new, _): "l\(files.indices.contains(file) ? files[file].file.path : ""):\(kind):\(old ?? 0):\(new ?? 0)"
        case .fold(let file, let region, _): "f\(file):\(region)"
        case .note(let file, _): "n\(file)"
        }
    }
}
