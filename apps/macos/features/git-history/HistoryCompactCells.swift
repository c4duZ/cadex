import AppKit
import UILooks

/// A commit's text: its subject over its author, time and SHA, after the lane and its gap
/// (components.inspector.commit), 2 pt between the lines.
@MainActor
final class HistoryCompactCell: NSTableCellView {
    typealias C = DesignTokens.Inspector.Commit
    let top = NSTextField(labelWithString: "")
    let bottom = NSTextField(labelWithString: "")

    init(identifier: String) {
        super.init(frame: .zero)
        self.identifier = .init(identifier)
        bottom.font = UILooks.font(DesignTokens.Inspector.Commit.Meta.fontSize)
        bottom.textColor = DesignTokens.Inspector.Commit.Meta.color
        for label in [top, bottom] {
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.translatesAutoresizingMaskIntoConstraints = false
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        addSubview(top)
        addSubview(bottom)
        let left = UILooks.pt(C.gap) - UILooks.labelInset
        let right = UILooks.pt(C.padding.right) - UILooks.labelInset
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(C.padding.top)),
            top.leadingAnchor.constraint(equalTo: leadingAnchor, constant: left),
            top.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -right),
            bottom.topAnchor.constraint(equalTo: top.bottomAnchor, constant: UILooks.pt(C.lineGap)),
            bottom.leadingAnchor.constraint(equalTo: leadingAnchor, constant: left),
            bottom.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -right),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("HistoryCompactCell is created in code") }
}

/// A row of the compact history: the open commit and its files drawn as one chosen box, as the
/// drawing has it (the files sat outside it, 2026-11-17); the table's own selection is not drawn
/// (a click opens, it does not select).
final class HistoryCompactRowView: NSTableRowView {
    enum Part { case none, whole, top, middle, bottom }
    var part = Part.none { didSet { needsDisplay = true } }

    override func drawBackground(in dirtyRect: NSRect) {
        guard part != .none else { return }
        typealias Tree = DesignTokens.Inspector.Tree
        let radius = UILooks.pt(DesignTokens.Inspector.Commit.radius)
        // The box runs on past the edges that join a neighbour, cut at the row: one box over many.
        var box = bounds
        if part == .top || part == .middle { box.size.height += radius * 2; if !isFlipped { box.origin.y -= radius * 2 } }
        if part == .bottom || part == .middle { box.size.height += radius * 2; if isFlipped { box.origin.y -= radius * 2 } }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        Tree.Selected.bg.setFill()
        NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).fill()
        if let line = Tree.Selected.shadow.first {
            line.color.setStroke()
            let border = NSBezierPath(roundedRect: box.insetBy(dx: line.spread / 2, dy: line.spread / 2), xRadius: radius, yRadius: radius)
            border.lineWidth = line.spread
            border.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func drawSelection(in dirtyRect: NSRect) {}
}

/// A file of the open commit: its letter in 14 pt, the path cut in the middle, + and − on the
/// right (components.inspector.commit.file).
@MainActor
final class HistoryCompactFileCell: NSTableCellView {
    typealias F = DesignTokens.Inspector.Commit.File
    private let letter = NSTextField(labelWithString: "")
    private let path = NSTextField(labelWithString: "")
    private let added = NSTextField(labelWithString: "")
    private let removed = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = .init("compactFile")
        letter.font = UILooks.font(DesignTokens.FontSize.chip, weight: DesignTokens.FontWeight.bold)
        path.font = UILooks.font(F.fontSize)
        path.textColor = F.color
        path.lineBreakMode = .byTruncatingMiddle
        path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        path.setContentHuggingPriority(.init(1), for: .horizontal)
        for (field, color) in [(added, DesignTokens.Color.accentGreenText), (removed, DesignTokens.Color.accentRedText)] {
            field.font = UILooks.font(DesignTokens.FontSize.caption)
            field.textColor = color
        }
        let row = NSStackView(views: [letter, path, added, removed])
        row.spacing = UILooks.pt(DesignTokens.Inspector.FileRow.gap)
        // In the subject's column (after the lane's gap), then the file row's own padding.
        let inset = UILooks.labelInset
        let commit = DesignTokens.Inspector.Commit.self
        row.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(commit.gap + F.padding.left) - inset, bottom: 0,
                                      right: UILooks.pt(commit.padding.right + F.padding.right) - inset)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        // Its 24 pt at the top: the rest of the row is the gap to the next file, or the commit's
        // bottom padding under the last one.
        NSLayoutConstraint.activate([
            letter.widthAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Inspector.FileRow.Kind.width)),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.heightAnchor.constraint(equalToConstant: UILooks.rowHeight(F.height)),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("HistoryCompactFileCell is created in code") }

    func show(_ file: CommitDetails.File, color: NSColor) {
        letter.stringValue = String(file.letter)
        letter.textColor = color
        path.stringValue = file.path
        added.stringValue = file.added.map { "+\($0)" } ?? ""
        removed.stringValue = file.removed.map { "−\($0)" } ?? ""
    }
}

/// A branch or tag as the drawing's chip: rounded, 1 by 6 pt around the name, laid in the subject's
/// line as an image (a background color in the text had square corners and no padding, 2026-11-17).
@MainActor
enum HistoryRefChip {
    typealias R = DesignTokens.Inspector.Commit.Ref

    static func make(_ name: String, besides font: NSFont) -> NSAttributedString {
        let text = NSAttributedString(string: name, attributes: [
            .font: UILooks.font(R.fontSize, weight: R.weight), .foregroundColor: R.color,
        ])
        let size = text.size()
        let box = NSSize(width: ceil(size.width) + UILooks.pt(R.padding.left + R.padding.right),
                         height: ceil(size.height) + UILooks.pt(R.padding.top + R.padding.bottom))
        let image = NSImage(size: box, flipped: false) { rect in
            R.bg.setFill()
            NSBezierPath(roundedRect: rect, xRadius: UILooks.pt(R.radius), yRadius: UILooks.pt(R.radius)).fill()
            text.draw(at: NSPoint(x: UILooks.pt(R.padding.left), y: UILooks.pt(R.padding.bottom)))
            return true
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        // Centered on the subject's lowercase letters, as flex's align-items: center.
        attachment.bounds = NSRect(x: 0, y: (font.xHeight - box.height) / 2, width: box.width, height: box.height)
        return NSAttributedString(attachment: attachment)
    }
}
