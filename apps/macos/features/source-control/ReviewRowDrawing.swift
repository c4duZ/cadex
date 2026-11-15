import AppKit
import Editor
import Strings

/// How each row of the review is drawn: only the rows that cross the dirty
/// rect, each from its file's text colored once by the editor's coloring
/// (on first sight, then kept), numbers of both sides in the gutter.
extension ReviewTextView {
    override func draw(_ dirtyRect: NSRect) {
        look.background.setFill()
        dirtyRect.fill()
        guard let first = row(at: max(dirtyRect.minY, 0)) else { return }
        let lines = Set(marked)
        var index = first
        while index < layout.rows.count, tops[index] < dirtyRect.maxY {
            draw(layout.rows[index], in: rect(of: index), marked: lines.contains(index), cursor: index == cursor)
            index += 1
        }
    }

    private func draw(_ row: ReviewLayout.Row, in rect: NSRect, marked: Bool, cursor: Bool) {
        switch row {
        case .header(let file): drawHeader(file, in: rect)
        case .line(let file, let kind, let old, let new, _): drawLine(row, file: file, kind: kind, old: old, new: new, in: rect, marked: marked)
        case .fold(_, _, let count):
            label(T("⋯ Show \(count) more lines", "⋯ Mostrar mais \(count) linhas"), at: NSPoint(x: gutterWidth + 8, y: rect.minY + 2), color: look.lineNumber)
        case .note(_, let text):
            label(text, at: NSPoint(x: gutterWidth + 8, y: rect.minY + 2), color: look.lineNumber)
        case .image:
            break  // its ImageDiffView sits over the row
        case .annotation(_, let index):
            if layout.annotations.indices.contains(index) { drawAnnotation(layout.annotations[index], in: rect) }
        }
        if cursor, window?.firstResponder === self {
            look.foreground.withAlphaComponent(0.35).setStroke()
            let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawHeader(_ file: Int, in rect: NSRect) {
        guard files.indices.contains(file) else { return }
        let f = files[file].file
        look.foreground.withAlphaComponent(0.07).setFill()
        NSRect(x: 0, y: rect.minY + 6, width: rect.width, height: rect.height - 6).fill()
        let name = f.orig.isEmpty ? f.path : "\(f.orig) → \(f.path)"
        let counts = f.added.map { "+\($0) −\(f.removed ?? 0)" } ?? T("binary", "binário")
        let y = rect.minY + 6 + (rect.height - 6 - lineHeight) / 2 + 1
        label(String(f.status), at: NSPoint(x: 10, y: y), color: Self.statusColor(f.status), weight: .bold)
        label(name, at: NSPoint(x: 10 + charWidth * 2.5, y: y), color: look.foreground, weight: .semibold)
        let width = (counts as NSString).size(withAttributes: [.font: look.font]).width
        label(counts, at: NSPoint(x: rect.maxX - width - 12, y: y), color: look.lineNumber)
    }

    private func drawLine(_ row: ReviewLayout.Row, file: Int, kind: ReviewLayout.Kind, old: Int?, new: Int?, in rect: NSRect, marked: Bool) {
        switch kind {
        case .added: NSColor.systemGreen.withAlphaComponent(0.13).setFill(); rect.fill()
        case .removed: NSColor.systemRed.withAlphaComponent(0.13).setFill(); rect.fill()
        case .context: break
        }
        if marked {
            NSColor.controlAccentColor.withAlphaComponent(0.28).setFill()
            NSRect(x: 0, y: rect.minY, width: gutterWidth, height: rect.height).fill()
        }
        if hovered.map({ rect.minY >= tops[$0] && rect.minY < tops[$0 + 1] }) == true {
            label("+", at: NSPoint(x: 3, y: rect.minY + 1), color: .controlAccentColor, weight: .bold)
        }
        let numberWidth = (gutterWidth - Self.plusWidth - charWidth - 10) / 2
        let left = Self.plusWidth
        if let old { number(old, rightAt: left + numberWidth - 6, y: rect.minY) }
        if let new { number(new, rightAt: left + numberWidth * 2 - 6, y: rect.minY) }
        let sign = kind == .added ? "+" : kind == .removed ? "−" : ""
        label(sign, at: NSPoint(x: left + numberWidth * 2 + 2, y: rect.minY + 1), color: kind == .added ? .systemGreen : .systemRed)
        let text = lineText(file: file, side: kind == .removed ? "before" : "after", number: kind == .removed ? old : (new ?? old))
        let box = NSRect(x: gutterWidth + 8, y: rect.minY + 1, width: rect.width - gutterWidth - 16, height: rect.height)
        text.draw(with: box, options: wrap ? [.usesLineFragmentOrigin] : [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    /// A line's colored text, with tabs as 4 spaces and, when asked, the
    /// spaces and tabs shown as · and →.
    private func lineText(file: Int, side: String, number: Int?) -> NSAttributedString {
        guard let number, files.indices.contains(file) else { return NSAttributedString() }
        let key = "\(file):\(side)"
        if colored[key] == nil {
            let diff = files[file]
            let lines = side == "before" ? diff.before : diff.after
            let whole = EditorColoring.attributed(lines.joined(separator: "\n"), fileName: diff.file.path)
            var ranges: [NSRange] = []
            var at = 0
            for line in lines {
                let length = (line as NSString).length
                ranges.append(NSRange(location: at, length: length))
                at += length + 1
            }
            colored[key] = (whole, ranges)
        }
        guard let (whole, ranges) = colored[key], ranges.indices.contains(number - 1), NSMaxRange(ranges[number - 1]) <= whole.length else {
            return NSAttributedString()
        }
        let piece = NSMutableAttributedString(attributedString: whole.attributedSubstring(from: ranges[number - 1]))
        piece.addAttribute(.font, value: look.font, range: NSRange(location: 0, length: piece.length))
        Self.marks(in: piece, show: showWhitespace, color: look.lineNumber)
        return piece
    }

    private static func marks(in text: NSMutableAttributedString, show: Bool, color: NSColor) {
        let pattern = show ? ["\t": "→   ", " ": "·"] : ["\t": "    "]
        for (from, to) in pattern {
            var search = NSRange(location: 0, length: text.length)
            while true {
                let found = (text.string as NSString).range(of: from, options: [], range: search)
                guard found.location != NSNotFound else { break }
                text.replaceCharacters(in: found, with: to)
                if show { text.addAttribute(.foregroundColor, value: color, range: NSRange(location: found.location, length: (to as NSString).length)) }
                let next = found.location + (to as NSString).length
                search = NSRange(location: next, length: text.length - next)
            }
        }
    }

    /// A comment box under its lines: an accent bar, the title, the text.
    private func drawAnnotation(_ note: ReviewAnnotation, in rect: NSRect) {
        let box = NSRect(x: gutterWidth + 4, y: rect.minY + 4, width: rect.width - gutterWidth - 16, height: rect.height - 8)
        (note.stale ? NSColor.systemOrange : NSColor.controlAccentColor).withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        (note.stale ? NSColor.systemOrange : NSColor.controlAccentColor).setFill()
        NSRect(x: box.minX, y: box.minY, width: 3, height: box.height).fill()
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: look.lineNumber]
        (note.title as NSString).draw(at: NSPoint(x: box.minX + 12, y: box.minY + 5), withAttributes: titleAttributes)
        let body = NSRect(x: box.minX + 12, y: box.minY + lineHeight + 6, width: box.width - 24, height: box.height - lineHeight - 8)
        (note.text as NSString).draw(with: body, options: [.usesLineFragmentOrigin],
                                     attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: look.foreground])
    }

    private func number(_ value: Int, rightAt x: CGFloat, y: CGFloat) {
        let text = "\(value)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: look.font, .foregroundColor: look.lineNumber]
        text.draw(at: NSPoint(x: x - text.size(withAttributes: attributes).width, y: y + 1), withAttributes: attributes)
    }

    private func label(_ text: String, at point: NSPoint, color: NSColor, weight: NSFont.Weight = .regular) {
        let font = weight == .regular ? look.font : NSFontManager.shared.convert(look.font, toHaveTrait: .boldFontMask)
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    static func statusColor(_ status: Character) -> NSColor {
        switch status {
        case "A", "?": .systemGreen
        case "D": .systemRed
        case "R": .systemBlue
        default: .systemOrange
        }
    }
}
