import AppKit
import Menus
import UILooks

/// A box of the board that runs `onPress` on a click.
@MainActor
final class BoardBox: NSView {
    var onPress: (() -> Void)?
    /// The right click's entries, given by the app (each runs a command or the same thing as a click);
    /// cards and rows had none (UX audit, 2026-11-18).
    var rightMenu: (() -> [MenuEntry])?
    override func rightMouseDown(with event: NSEvent) {
        guard let entries = rightMenu?(), !entries.isEmpty else { return super.rightMouseDown(with: event) }
        PopupMenu.show(entries, at: convert(event.locationInWindow, from: nil), in: self)
    }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { if onPress != nil { addCursorRect(bounds, cursor: .pointingHand) } }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }

    func hold(_ content: NSView, padding: NSEdgeInsets) {
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(padding.left)),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(padding.right)),
            content.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(padding.top)),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -UILooks.pt(padding.bottom)),
        ])
    }
}

/// The board's page: the filters' row on top, then the columns in a scroll view, four side by
/// side on a wide window, two on a medium one, one on a narrow one (components.board.minColumn).
@MainActor
final class BoardPage: NSView {
    /// Esc: leave the board (BoardActions.back).
    var onEscape: () -> Void = {}
    override var acceptsFirstResponder: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape() }
    private let bar = BoardWrap()
    private let scroll = NSScrollView()
    private let content = BoardContent()
    private var columns: [NSView] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        typealias F = BD.Filters
        bar.gap = UILooks.pt(F.gap)
        bar.padding = F.padding
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = content
        for view in [bar, scroll] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor), bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("BoardPage is created in code") }

    override var isFlipped: Bool { true }

    func show(pills: [NSView], buttons: [NSView], columns: [NSView]) {
        bar.set(left: pills, right: buttons)
        self.columns = columns
        perRow = 0
        needsLayout = true
    }

    private var perRow = 0
    private let rows = NSStackView()

    override func layout() {
        super.layout()
        let pad = BD.padding
        let width = bounds.width - UILooks.pt(pad.left + pad.right)
        guard width > 0 else { return }
        let gap = UILooks.pt(BD.columnGap)
        let minimum = UILooks.pt(BD.minColumn)
        let wanted = width >= minimum * 4 + gap * 3 ? 4 : width >= minimum * 2 + gap ? 2 : 1
        guard wanted != perRow else { return }
        perRow = wanted
        arrange(gap: gap)
    }

    /// The columns in rows of `perRow`, each row's columns one width.
    private func arrange(gap: CGFloat) {
        let pad = BD.padding
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        columns.forEach { $0.removeFromSuperview() }
        if rows.superview == nil {
            rows.orientation = .vertical
            rows.alignment = .leading
            rows.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(rows)
            NSLayoutConstraint.activate([
                rows.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: UILooks.pt(pad.left)),
                rows.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -UILooks.pt(pad.right)),
                rows.topAnchor.constraint(equalTo: content.topAnchor, constant: UILooks.pt(pad.top)),
                rows.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -UILooks.pt(pad.bottom)),
            ])
        }
        rows.spacing = gap * 2
        for start in stride(from: 0, to: columns.count, by: perRow) {
            var group = Array(columns[start..<min(start + perRow, columns.count)])
            // A last row with fewer columns keeps their width: empty ones fill it.
            while group.count < perRow { group.append(NSView()) }
            group.forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
            let row = NSStackView(views: group)
            row.alignment = .top
            row.distribution = .fillEqually
            row.spacing = gap
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
    }
}

/// The scroll view's document, top-down.
final class BoardContent: NSView {
    override var isFlipped: Bool { true }
}

/// The filters' row: the pills from the left and the buttons at the right, on one line when they
/// fit, the buttons on a line of their own and the pills wrapping on a narrow window.
@MainActor
final class BoardWrap: NSView {
    var gap: CGFloat = 0
    var padding = NSEdgeInsetsZero
    private var left: [NSView] = []
    private var right: [NSView] = []
    private var height: CGFloat = 0
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: height) }

    func set(left: [NSView], right: [NSView]) {
        subviews.forEach { $0.removeFromSuperview() }
        self.left = left
        self.right = right
        (left + right).forEach { $0.translatesAutoresizingMaskIntoConstraints = true; addSubview($0) }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let inner = bounds.width - UILooks.pt(padding.left + padding.right)
        guard inner > 0 else { return }
        let sizes = { (views: [NSView]) in views.map(\.fittingSize) }
        let leftSizes = sizes(left), rightSizes = sizes(right)
        let rightWidth = rightSizes.reduce(0) { $0 + $1.width } + gap * CGFloat(max(rightSizes.count - 1, 0))
        let leftWidth = leftSizes.reduce(0) { $0 + $1.width } + gap * CGFloat(max(leftSizes.count - 1, 0))
        let together = leftWidth + gap * 2 + rightWidth <= inner
        let line = (leftSizes + rightSizes).map(\.height).max() ?? 0
        var x = UILooks.pt(padding.left), y = UILooks.pt(padding.top)
        if !together {
            // The buttons first, on their own line at the right.
            var bx = UILooks.pt(padding.left) + inner - rightWidth
            for (view, size) in zip(right, rightSizes) {
                view.frame = CGRect(x: bx, y: y + (line - size.height) / 2, width: size.width, height: size.height)
                bx += size.width + gap
            }
            y += line + gap
        }
        for (view, size) in zip(left, leftSizes) {
            if x > UILooks.pt(padding.left), x + size.width > UILooks.pt(padding.left) + inner { x = UILooks.pt(padding.left); y += line + gap }
            view.frame = CGRect(x: x, y: y + (line - size.height) / 2, width: min(size.width, inner), height: size.height)
            x += size.width + gap
        }
        if together {
            var bx = UILooks.pt(padding.left) + inner - rightWidth
            for (view, size) in zip(right, rightSizes) {
                view.frame = CGRect(x: bx, y: UILooks.pt(padding.top) + (line - size.height) / 2, width: size.width, height: size.height)
                bx += size.width + gap
            }
        }
        let total = y + line + UILooks.pt(padding.bottom)
        if total != height {
            height = total
            invalidateIntrinsicContentSize()
        }
    }
}
