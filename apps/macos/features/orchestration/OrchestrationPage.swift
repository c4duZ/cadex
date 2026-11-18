import AppKit
import StateGlyph
import UILooks

/// The new frame's face for the orchestration's pages (a run, an automation's history; plan 30
/// B): the project page's measures (components.project), the board's cards (components.board).
/// A scroll view whose column of sections fills the page's width.
@MainActor
final class OrchestrationPage: NSView {
    private let scroll = NSScrollView()
    private let column = NSStackView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = DesignTokens.Color.bgWindow.cgColor
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = UILooks.pt(DesignTokens.Project.gap)
        column.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(column)
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        let pad = DesignTokens.Project.padding
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            column.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: UILooks.pt(pad.left)),
            column.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -UILooks.pt(pad.right)),
            column.topAnchor.constraint(equalTo: document.topAnchor, constant: UILooks.pt(pad.top)),
            column.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -UILooks.pt(pad.bottom)),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("OrchestrationPage is created in code") }

    override var isFlipped: Bool { true }

    /// The sections, each across the page.
    func show(_ sections: [NSView]) {
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for view in sections {
            column.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }
    }

    // MARK: Pieces

    /// The page's head: the name big, the line under it, and the buttons on the right.
    static func head(_ name: String, meta: String, buttons: [NSView]) -> NSView {
        let words = stack([boardLabel(name, size: DesignTokens.Project.Title.fontSize, color: DesignTokens.Color.textPrimary,
                                      weight: DesignTokens.Project.Title.weight),
                           boardLabel(meta, size: DesignTokens.FontSize.body, color: DesignTokens.Project.Head.meta)],
                          gap: DesignTokens.Project.Head.titleGap)
        words.setContentHuggingPriority(.init(1), for: .horizontal)
        let tail = NSStackView(views: buttons)
        tail.spacing = UILooks.pt(DesignTokens.Project.Head.gap) / 2
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [words, spacer, tail])
        row.alignment = .bottom
        row.distribution = .fill
        row.spacing = UILooks.pt(DesignTokens.Project.Head.gap)
        return row
    }

    /// "TASKS", "INBOX", "RUNS".
    static func section(_ text: String) -> NSTextField {
        typealias L = DesignTokens.Project.Label
        let label = boardLabel(text, size: L.fontSize, color: L.color, weight: L.weight)
        label.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: UILooks.font(L.fontSize, weight: L.weight), .foregroundColor: L.color, .kern: UILooks.pt(L.fontSize) * L.tracking,
        ])
        return label
    }

    /// A card (components.board.card): the state's glyph and the title, the lines under it, the
    /// buttons; `indent` moves it right (a task one step deeper in its run's graph).
    static func card(state: GlyphState?, title: String, trailing: String = "", lines: [(String, NSColor)], buttons: [NSView], indent: Int = 0) -> NSView {
        typealias C = DesignTokens.Board.Card
        let name = boardLabel(title, size: DesignTokens.FontSize.body, color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.semibold)
        name.setContentHuggingPriority(.init(1), for: .horizontal)
        let age = boardLabel(trailing, size: C.Head.Age.fontSize, color: C.Head.Age.color)
        age.setContentCompressionResistancePriority(.required, for: .horizontal)
        let head = NSStackView(views: (state.map { [boardGlyph($0)] } ?? []) + [name, age])
        head.spacing = UILooks.pt(C.Head.gap)
        var views: [NSView] = [head]
        for (text, color) in lines where !text.isEmpty {
            let line = NSTextField(wrappingLabelWithString: text)
            line.font = UILooks.font(C.Text.fontSize)
            line.textColor = color
            line.maximumNumberOfLines = 3
            line.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            views.append(line)
        }
        if !buttons.isEmpty {
            let row = NSStackView(views: buttons)
            row.spacing = UILooks.pt(C.Meta.gap)
            views.append(row)
        }
        let inner = stack(views, gap: C.gap)
        for view in views.dropLast(buttons.isEmpty ? 0 : 1) { view.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true }
        let box = BoardBox()
        box.wantsLayer = true
        box.layer?.cornerRadius = UILooks.pt(C.radius)
        box.layer?.backgroundColor = C.bg.cgColor
        box.layer?.borderColor = C.border.cgColor
        box.layer?.borderWidth = DesignTokens.Stroke.hairline
        box.hold(inner, padding: NSEdgeInsets(top: C.padding, left: C.padding, bottom: C.padding, right: C.padding))
        guard indent > 0 else { return box }
        // The graph: a task one step right of the deepest task it waits for.
        let holder = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(box)
        let step = UILooks.pt(DesignTokens.Project.Head.gap) * 1.5 * CGFloat(min(indent, 8))
        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: step), box.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            box.topAnchor.constraint(equalTo: holder.topAnchor), box.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
        ])
        return holder
    }

    /// The app's small buttons (the board's height).
    static func button(_ title: String, primary: Bool = false, _ action: @escaping @MainActor () -> Void) -> NSView {
        DesignButton.make(title, primary ? .primary : .secondary, height: DesignTokens.Board.Actions.height, action: action)
    }

    static func stack(_ views: [NSView], gap: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = UILooks.pt(gap)
        return stack
    }
}
