import AppKit
import Icons
import Strings
import UILooks

/// One line of text with its matches marked (components.memoryPanel.search.hit): the amber text on
/// its chip, a rounded box padded around each match, the same in titles and snippets (the
/// board's one highlight). Cut at the end when long (the snippet stays one line).
@MainActor
final class PanelMarkedLabel: NSView {
    typealias H = MP.Search.Hit
    let marked: PanelMarked
    private let storage = NSTextStorage()
    private let manager = NSLayoutManager()
    private let container = NSTextContainer()
    private let font: NSFont

    init(_ marked: PanelMarked, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
        self.marked = marked
        font = UILooks.font(size, weight: weight)
        super.init(frame: .zero)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let text = NSMutableAttributedString(string: marked.text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
        let length = (marked.text as NSString).length
        for mark in marked.marks where NSMaxRange(mark) <= length {
            text.addAttribute(.foregroundColor, value: H.color, range: mark)
        }
        storage.setAttributedString(text)
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 1
        container.lineBreakMode = .byTruncatingTail
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(marked.text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelMarkedLabel is created in code") }

    override var isFlipped: Bool { true }

    /// The line's height with the marks' padding; as wide as the text, cut when the row is narrower.
    override var intrinsicContentSize: NSSize {
        let width = (marked.text as NSString).size(withAttributes: [.font: font]).width
        return NSSize(width: ceil(width) + UILooks.pt(H.padding.left + H.padding.right), height: ceil(manager.defaultLineHeight(for: font)) + 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        container.size = NSSize(width: max(1, bounds.width - UILooks.pt(H.padding.right)), height: bounds.height)
        let origin = NSPoint(x: UILooks.pt(H.padding.left), y: 1)
        let glyphs = manager.glyphRange(for: container)
        for mark in marked.marks {
            let range = manager.glyphRange(forCharacterRange: mark, actualCharacterRange: nil)
            guard NSIntersectionRange(range, glyphs).length > 0 else { continue }
            var rect = manager.boundingRect(forGlyphRange: NSIntersectionRange(range, glyphs), in: container)
            rect = rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -UILooks.pt(H.padding.left), dy: -1)
            H.bg.setFill()
            NSBezierPath(roundedRect: rect, xRadius: UILooks.pt(H.radius), yRadius: UILooks.pt(H.radius)).fill()
        }
        manager.drawGlyphs(forGlyphRange: glyphs, at: origin)
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }
}

/// A result (MemorySearch.dc.html): the title, the snippet on one line, "projeto · caminho", and
/// with "Explicar classificação" the hit's trace folded under it. A click opens the page.
@MainActor
final class PanelHitRow: PanelPress {
    typealias R = MP.Search.Result
    let hit: PanelHit
    private var traceOpen = false
    private let traceHost = PanelText.column([], gap: 2)
    private var toggle: PanelPress?
    var chosen = false { didSet { layer?.backgroundColor = chosen ? MP.Nav.Row.Selected.bg.cgColor : nil } }

    init(_ hit: PanelHit, words: String, open: @escaping () -> Void) {
        self.hit = hit
        super.init(frame: .zero)
        let title = PanelMarkedLabel(PanelMarked(text: hit.title, words: MP.Search.Hit.inTitle ? words : ""), size: DesignTokens.FontSize.body,
                                     color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.semibold)
        let snippet = PanelMarkedLabel(hit.snippet, size: DesignTokens.FontSize.panel, color: R.snippet)
        let place = PanelText.line(PanelGraph.name(hit.project) + " · " + hit.path, size: DesignTokens.FontSize.meta, color: MP.Head.meta)
        var views: [NSView] = [title, snippet, place]
        if hit.trace != nil { views.append(traceToggle()) }
        views.append(traceHost)
        let column = PanelText.column(views, gap: R.gap)
        for view in views { view.widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor).isActive = true }
        hold(column, padding: R.padding)
        box(bg: nil, border: nil, radius: MP.Nav.Row.radius)
        onPress = open
        setAccessibilityElement(true)
        setAccessibilityRole(.link)
        setAccessibilityLabel(hit.title + ", " + PanelGraph.name(hit.project) + " · " + hit.path)
        setAccessibilityHelp(hit.snippet.text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelHitRow is created in code") }

    private func traceToggle() -> NSView {
        let line = PanelText.line(hit.trace?.line ?? "", size: DesignTokens.FontSize.meta, color: MP.Head.meta)
        line.font = UILooks.monospaced(MP.Mono.fontSize)
        let caret = NSImageView(image: Icon.caretRight.image(size: UILooks.pt(MP.Chip.dot * 2)))
        caret.contentTintColor = MP.Breadcrumb.color
        let press = PanelPress()
        press.hold(PanelText.row([caret, line], gap: MP.Chip.gap), padding: NSEdgeInsets())
        press.onPress = { [weak self, weak caret] in
            guard let self else { return }
            self.traceOpen.toggle()
            caret?.image = (self.traceOpen ? Icon.caretDown : Icon.caretRight).image(size: UILooks.pt(MP.Chip.dot * 2))
            self.traceHost.setViews(self.traceOpen ? self.traceRows() : [], in: .top)
        }
        toggle = press
        press.setAccessibilityElement(true)
        press.setAccessibilityRole(.disclosureTriangle)
        press.setAccessibilityLabel(T("Ranking", "Classificação") + ": " + (hit.trace?.line ?? ""))
        return press
    }

    /// The stream table: stream, rank, raw score, RRF; then the entities and "alcançado por".
    func traceRows() -> [NSView] {
        guard let trace = hit.trace else { return [] }
        let head = [T("Stream", "Stream"), T("Rank", "Posição"), T("Raw score", "Pontuação bruta"), "RRF"]
        var rows = [cells(head, color: MP.Head.meta)]
        rows += trace.streams.map { cells([$0.stream, $0.rank, $0.raw, $0.rrf], color: DesignTokens.Color.textBody) }
        if !trace.entities.isEmpty { rows.append(PanelScreen.note(T("Matched entities: ", "Entidades encontradas: ") + trace.entities)) }
        if let via = trace.via { rows.append(PanelScreen.note(T("Reached through ", "Alcançada por ") + via)) }
        return rows
    }

    private func cells(_ values: [String], color: NSColor) -> NSView {
        let labels = values.map { value -> NSView in
            let label = PanelText.line(value, size: MP.Mono.fontSize, color: color)
            label.font = UILooks.monospaced(MP.Mono.fontSize)
            label.widthAnchor.constraint(equalToConstant: UILooks.pt(MP.Aside.width) * 0.65).isActive = true
            return label
        }
        return PanelText.row(labels, gap: MP.Chip.gap)
    }

    /// For tests.
    func toggleTrace() { toggle?.onPress?() }
    var traceShown: Int { traceHost.views.count }
}
