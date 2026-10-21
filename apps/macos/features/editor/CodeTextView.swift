import AppKit

/// The text view of the editor: an NSTextView (TextKit 2) that draws the
/// current line, indents with the file's own unit and answers edit.find
/// with the system's find bar (docs/spec/editor.md). edit.find reaches
/// showFind(_:) by its selector (FindTarget in the command palette), like
/// the terminal's.
final class CodeTextView: NSTextView {
    /// What Tab inserts: a tab or some spaces, detected from the file.
    var indentUnit = "    "
    var currentLineColor: NSColor = .quaternaryLabelColor {
        didSet { needsDisplay = true }
    }
    /// Lay out the whole text, not only what shows. TextKit 2 estimates the
    /// height of the lines off screen and corrects it while scrolling and
    /// typing: a wrapped Markdown note changed height by thousands of points
    /// and the text jumped (issue #2, measured 2026-10-21). Off for big files.
    var laysOutWholeText = false
    private var laidOutWidth: CGFloat = 0

    func layoutWholeText() {
        guard laysOutWholeText, let layout = textLayoutManager else { return }
        layout.ensureLayout(for: layout.documentRange)
        // The view takes the real height now, not at the next scroll.
        layout.textViewportLayoutController.layoutViewport()
    }

    /// A new width wraps the lines anew: lay them all out again, once the
    /// text container has it (on the frame change it still had the old one,
    /// and the layout made then was thrown away).
    override func layout() {
        super.layout()
        guard laysOutWholeText, let width = textContainer?.size.width, width != laidOutWidth else { return }
        laidOutWidth = width
        layoutWholeText()
    }

    /// edit.find (⌘F) with the editor focused.
    @objc func showFind(_ sender: Any?) {
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        performTextFinderAction(item)
    }

    /// ⌘+click on a character: true when it did something (opened a link),
    /// so the click does not move the cursor.
    var commandClick: ((Int) -> Bool)?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let commandClick {
            let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
            if commandClick(index) { return }
        }
        super.mouseDown(with: event)
    }

    override func insertTab(_ sender: Any?) {
        insertText(indentUnit, replacementRange: selectedRange())
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        needsDisplay = true
    }

    /// The line of the cursor, behind the text, the width of the view.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard selectedRange().length == 0, let frame = currentLineFrame() else { return }
        currentLineColor.setFill()
        NSRect(x: 0, y: frame.minY, width: bounds.width, height: frame.height).intersection(rect).fill()
    }

    /// The frame, in view coordinates, of the layout fragment holding the
    /// insertion point.
    func currentLineFrame() -> NSRect? {
        guard let layout = textLayoutManager, let storage = layout.textContentManager,
              let location = storage.location(storage.documentRange.location, offsetBy: selectedRange().location),
              let fragment = layout.textLayoutFragment(for: location) else { return nil }
        var frame = fragment.layoutFragmentFrame
        frame.origin.y += textContainerOrigin.y
        return frame
    }

    /// The tab or the number of spaces most lines start with.
    static func detectIndent(_ text: String) -> String {
        var tabs = 0
        var spaces: [Int: Int] = [:]
        for line in text.split(separator: "\n", maxSplits: 2000, omittingEmptySubsequences: true) {
            if line.hasPrefix("\t") { tabs += 1; continue }
            let n = line.prefix { $0 == " " }.count
            if n >= 2 { spaces[n, default: 0] += 1 }
        }
        let spaced = spaces.values.reduce(0, +)
        if tabs > spaced { return "\t" }
        // The smallest common indent is the unit (2 or 4 in practice).
        let unit = spaces.keys.filter { spaces[$0]! * 4 >= spaced / max(spaces.count, 1) }.min() ?? 4
        return String(repeating: " ", count: unit == 2 ? 2 : 4)
    }
}
