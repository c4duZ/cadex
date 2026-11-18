import AppKit
import Editor
import Strings
import UILooks

/// How each row of the review is drawn: only the rows that cross the dirty
/// rect, each from its file's text colored once by the editor's coloring
/// (on first sight, then kept), numbers of both sides in the gutter. The
/// frame's face (plan 31 A): the page's background, color.diff.* for the
/// lines, a file's header as a card row with the Changes' letter colors.
extension ReviewTextView {
    override func draw(_ dirtyRect: NSRect) {
        DesignTokens.Color.bgWindow.setFill()
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
            words(T("⋯ Show \(count) more lines", "⋯ Mostrar mais \(count) linhas"), at: NSPoint(x: gutterWidth + 8, y: rect.minY + 2),
                  color: DesignTokens.Color.accentLink)
        case .note(_, let text):
            words(text, at: NSPoint(x: gutterWidth + 8, y: rect.minY + 2), color: DesignTokens.Color.textMuted)
        case .image:
            break  // its ImageDiffView sits over the row
        case .annotation(_, let index):
            if layout.annotations.indices.contains(index) { drawAnnotation(layout.annotations[index], in: rect) }
        }
        if cursor, window?.firstResponder === self {
            DesignTokens.Color.lineFocus.setStroke()
            let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawHeader(_ file: Int, in rect: NSRect) {
        guard files.indices.contains(file) else { return }
        let f = files[file].file
        typealias F = DesignTokens.Inspector.FileRow
        // A card row across the page: the bar of a file in the stack (components.board.card's colors).
        let bar = NSRect(x: 0, y: rect.minY + 6, width: rect.width, height: rect.height - 6)
        DesignTokens.Color.bgCard.setFill()
        bar.fill()
        DesignTokens.Color.lineSubtle.setFill()
        NSRect(x: 0, y: bar.minY, width: bar.width, height: DesignTokens.Stroke.hairline).fill()
        NSRect(x: 0, y: bar.maxY - DesignTokens.Stroke.hairline, width: bar.width, height: DesignTokens.Stroke.hairline).fill()
        let folder = (f.path as NSString).deletingLastPathComponent
        let name = f.orig.isEmpty ? (f.path as NSString).lastPathComponent : "\(f.orig) → \(f.path)"
        let font = UILooks.font(DesignTokens.FontSize.body, weight: DesignTokens.FontWeight.semibold)
        let y = bar.midY - font.boundingRectForFont.height / 2 + 1
        let x = UILooks.pt(F.padding.left) + 4
        let letter = f.status == "?" ? "A" : String(f.status)
        words(letter, at: NSPoint(x: x, y: y), color: ChangesRowView.color(of: Character(letter)),
              font: UILooks.font(F.Kind.fontSize, weight: F.Kind.weight))
        let nameAt = NSPoint(x: x + UILooks.pt(F.Kind.width + F.gap), y: y)
        words(name, at: nameAt, color: DesignTokens.Color.textPrimary, font: font)
        if f.orig.isEmpty, !folder.isEmpty {
            let width = (name as NSString).size(withAttributes: [.font: font]).width
            words(folder, at: NSPoint(x: nameAt.x + width + UILooks.pt(F.gap), y: y + 1), color: F.dir)
        }
        let stopped = authorStopped.contains(file) ? T("authorship stopped (over 2 MB)", "autoria parada (mais de 2 MB)") : nil
        var right = bar.maxX - UILooks.pt(F.padding.right) - 8
        let counts: [(String, NSColor)] = f.added.map { [("+\($0)", DesignTokens.Color.accentGreenText), ("−\(f.removed ?? 0)", DesignTokens.Color.accentRedText)] }
            ?? [(T("binary", "binário"), DesignTokens.Color.textMuted)]
        for (text, color) in (counts + (stopped.map { [($0, DesignTokens.Color.textMuted)] } ?? [])).reversed() {
            let width = (text as NSString).size(withAttributes: [.font: UILooks.font(F.Count.fontSize)]).width
            right -= width
            words(text, at: NSPoint(x: right, y: y + 1), color: color, font: UILooks.font(F.Count.fontSize))
            right -= UILooks.pt(F.gap) / 2
        }
    }

    private func drawLine(_ row: ReviewLayout.Row, file: Int, kind: ReviewLayout.Kind, old: Int?, new: Int?, in rect: NSRect, marked: Bool) {
        switch kind {
        case .added: DesignTokens.Color.diffAddBg.setFill(); rect.fill()
        case .removed: DesignTokens.Color.diffDelBg.setFill(); rect.fill()
        case .context: break
        }
        if marked {
            DesignTokens.Color.accentLinkBg.setFill()
            NSRect(x: 0, y: rect.minY, width: gutterWidth, height: rect.height).fill()
        }
        // The agent's line: a thin bar at the edge (review.toggle-authorship).
        if kind != .removed, let new, authorMarks[file]?[new] != nil {
            DesignTokens.Color.stateReview.setFill()
            NSRect(x: 0, y: rect.minY, width: 3, height: rect.height).fill()
        }
        if hovered.map({ rect.minY >= tops[$0] && rect.minY < tops[$0 + 1] }) == true {
            label("+", at: NSPoint(x: 3, y: rect.minY + 1), color: DesignTokens.Color.accentLink, weight: .bold)
        }
        let numberWidth = (gutterWidth - Self.plusWidth - charWidth - 10) / 2
        let left = Self.plusWidth
        if let old { number(old, rightAt: left + numberWidth - 6, y: rect.minY) }
        if let new { number(new, rightAt: left + numberWidth * 2 - 6, y: rect.minY) }
        let sign = kind == .added ? "+" : kind == .removed ? "−" : ""
        label(sign, at: NSPoint(x: left + numberWidth * 2 + 2, y: rect.minY + 1), color: kind == .added ? DesignTokens.Color.accentGreenText : DesignTokens.Color.accentRedText)
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
            let whole = EditorLineColoring(lines.joined(separator: "\n"), fileName: diff.file.path)
            var ranges: [NSRange] = []
            var at = 0
            for line in lines {
                let length = (line as NSString).length
                ranges.append(NSRange(location: at, length: length))
                at += length + 1
            }
            colored[key] = (whole, ranges)
        }
        guard let (whole, ranges) = colored[key], ranges.indices.contains(number - 1) else { return NSAttributedString() }
        let piece = NSMutableAttributedString(attributedString: whole.attributed(ranges[number - 1]))
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
        (note.stale ? DesignTokens.Color.tintNeeds : DesignTokens.Color.accentLinkBg).setFill()
        NSBezierPath(roundedRect: box, xRadius: UILooks.pt(DesignTokens.Board.Card.radius), yRadius: UILooks.pt(DesignTokens.Board.Card.radius)).fill()
        (note.stale ? DesignTokens.Color.stateNeeds : DesignTokens.Color.accentLink).setFill()
        NSRect(x: box.minX, y: box.minY, width: 3, height: box.height).fill()
        let titleAttributes: [NSAttributedString.Key: Any] = [.font: UILooks.font(DesignTokens.FontSize.caption, weight: DesignTokens.FontWeight.semibold), .foregroundColor: DesignTokens.Color.textSecondary]
        (note.title as NSString).draw(at: NSPoint(x: box.minX + 12, y: box.minY + 5), withAttributes: titleAttributes)
        let body = NSRect(x: box.minX + 12, y: box.minY + lineHeight + 6, width: box.width - 24, height: box.height - lineHeight - 8)
        (note.text as NSString).draw(with: body, options: [.usesLineFragmentOrigin],
                                     attributes: [.font: UILooks.font(DesignTokens.FontSize.meta), .foregroundColor: DesignTokens.Color.textBody])
    }

    private func number(_ value: Int, rightAt x: CGFloat, y: CGFloat) {
        let text = "\(value)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: look.font, .foregroundColor: DesignTokens.Color.textTertiary]
        text.draw(at: NSPoint(x: x - text.size(withAttributes: attributes).width, y: y + 1), withAttributes: attributes)
    }

    private func label(_ text: String, at point: NSPoint, color: NSColor, weight: NSFont.Weight = .regular) {
        let font = weight == .regular ? look.font : NSFontManager.shared.convert(look.font, toHaveTrait: .boldFontMask)
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    /// Words of the interface (a fold, a note, the header), in its font, not the code's.
    private func words(_ text: String, at point: NSPoint, color: NSColor, font: NSFont = UILooks.font(DesignTokens.FontSize.meta)) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }
}
