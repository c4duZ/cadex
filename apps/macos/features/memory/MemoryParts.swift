import AppKit
import Icons
import Strings
import UILooks

/// The pieces of the Memory tab as the Inspector mockup draws them (components.inspector.memory):
/// the search box, the section labels, the cards, the briefing's note.
@MainActor
enum MemoryParts {
    typealias M = DesignTokens.Inspector.Memory

    /// A muted line (the engine's state, an empty wiki).
    static func line(_ text: String) -> NSTextField {
        MemoryText.label(text, size: M.Card.Meta.fontSize, color: M.Card.Meta.color, wraps: true)
    }

    static func paragraph(_ text: String) -> NSTextField {
        MemoryText.label(text, size: M.Briefing.fontSize, color: M.Briefing.color, wraps: true)
    }

    /// "LEARNED TODAY", "WIKI": small caps-like, tracked, dim.
    static func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: UILooks.font(M.Label.fontSize, weight: M.Label.weight), .foregroundColor: M.Label.color,
            .kern: UILooks.pt(M.Label.tracking * M.Label.fontSize),
        ])
        return field
    }

    /// A label over its cards.
    static func section(_ title: String, count: Int? = nil, _ cards: [NSView]) -> NSView {
        let head = label(title)
        if let count {
            // The count beside it, dimmer (the proposal's `.lbl .n`).
            let text = NSMutableAttributedString(attributedString: head.attributedStringValue)
            text.append(NSAttributedString(string: "  \(count)", attributes: [
                .font: UILooks.font(M.Label.fontSize, weight: .semibold), .foregroundColor: DesignTokens.Color.textSeparator,
            ]))
            head.attributedStringValue = text
        }
        // The title at the rows' words, not at their lit box's edge.
        let titled = NSStackView(views: [head])
        titled.edgeInsets = NSEdgeInsets(top: 0, left: MemoryAge.inset, bottom: 0, right: 0)
        let stack = NSStackView(views: [titled] + cards)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = UILooks.pt(M.learnedGap)
        for card in cards { card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }

    /// "Search what this project knows": a box that opens the search (memory.search).
    static func search(_ press: @escaping @MainActor () -> Void) -> NSView {
        let icon = NSImageView(image: Icon.magnifyingGlass.image(size: UILooks.pt(M.Search.icon)))
        icon.contentTintColor = M.Search.color
        let text = MemoryText.label(T("Search memory", "Buscar na memória"), size: DesignTokens.FontSize.body, color: M.Search.color)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let box = MemoryBox(views: [icon, text, spacer], press: press)
        box.spacing = UILooks.pt(M.WikiRow.gap)
        box.edgeInsets = insets(M.Search.padding)
        box.layer?.backgroundColor = M.Search.bg.cgColor
        box.layer?.borderColor = M.Search.border.cgColor
        box.layer?.borderWidth = DesignTokens.Stroke.hairline
        box.layer?.cornerRadius = UILooks.pt(M.Search.radius)
        box.setAccessibilityLabel(text.stringValue)
        return box
    }

    /// A card: the title in semibold over its "kind · where it came from".
    static func card(_ title: String, meta: String, press: (@MainActor () -> Void)? = nil) -> NSStackView {
        // Both wrap: a long title or summary is read whole, not cut on one line.
        let views: [NSView] = [MemoryText.label(title, size: DesignTokens.FontSize.body, weight: M.Card.title, color: DesignTokens.Color.textPrimary, wraps: true),
                               MemoryText.label(meta, size: M.Card.Meta.fontSize, color: M.Card.Meta.color, wraps: true)]
        let box = MemoryBox(views: views, press: press)
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = UILooks.pt(M.Card.gap)
        box.edgeInsets = insets(M.Card.padding)
        box.layer?.backgroundColor = M.Card.bg.cgColor
        box.layer?.cornerRadius = UILooks.pt(M.Card.radius)
        return box
    }

    /// A proposal waiting for the owner: its card with Approve and Reject.
    static func proposal(_ proposal: MemoryProposal, approve: @escaping @MainActor () -> Void, reject: @escaping @MainActor () -> Void) -> NSView {
        let meta = [proposal.kind, proposal.summary].filter { !$0.isEmpty }.joined(separator: " · ")
        let box = card(proposal.title, meta: meta)
        if !proposal.preview.isEmpty { box.addArrangedSubview(MemoryText.label(proposal.preview, size: M.Card.Meta.fontSize, color: M.Card.Meta.color)) }
        let small = DesignTokens.Button.Heights.small
        let buttons = NSStackView(views: [DesignButton.make(T("Approve", "Aprovar"), .primary, height: small, action: approve),
                                          DesignButton.make(T("Reject", "Rejeitar"), .secondary, height: small, action: reject)])
        buttons.spacing = UILooks.pt(M.WikiRow.gap)
        box.addArrangedSubview(buttons)
        return box
    }

    static func button(_ title: String, _ press: @escaping @MainActor () -> Void) -> NSView {
        DesignButton.make(title, .secondary, action: press)
    }

    /// "Each new agent here starts with a briefing of this. See the briefing": the note at the foot.
    /// "Configure this project…": its .ai-memory.toml on a screen, in the settings (plan 32 D).
    static func configure(_ open: @escaping @MainActor () -> Void) -> NSView {
        let field = NSTextField(labelWithString: T("Configure this project's memory…", "Configurar a memória deste projeto…"))
        field.font = UILooks.font(M.Briefing.fontSize)
        field.textColor = DesignTokens.Color.textPrimary
        field.isSelectable = false
        return MemoryBox(views: [field], press: open)
    }

    /// The proposal's foot (`.foot`): one card, "Every new agent here starts with the briefing of
    /// this." and two links, See the briefing and Configure, each running its command.
    static func foot(see: @escaping @MainActor () -> Void, configure: @escaping @MainActor () -> Void) -> NSView {
        let words = MemoryText.label(T("Every new agent here starts with the briefing of this.", "Todo agente novo aqui começa com o briefing disto."),
                                     size: M.Briefing.fontSize, color: M.Briefing.color, wraps: true)
        func link(_ title: String, _ press: @escaping @MainActor () -> Void) -> NSView {
            MemoryBox(views: [MemoryText.label(title, size: M.Briefing.fontSize, color: DesignTokens.Color.accentLink)], press: press)
        }
        let dot = MemoryText.label("·", size: M.Briefing.fontSize, color: M.Briefing.color)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let links = NSStackView(views: [link(T("See the briefing", "Ver o briefing"), see), dot, link(T("Configure", "Configurar"), configure), spacer])
        links.spacing = UILooks.pt(M.WikiRow.gap)
        links.distribution = .fill
        let column = NSStackView(views: [words, links])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = UILooks.pt(M.Card.gap)
        let box = NSStackView(views: [column])
        box.wantsLayer = true
        box.edgeInsets = NSEdgeInsets(top: UILooks.pt(M.Briefing.padding), left: UILooks.pt(M.Briefing.padding),
                                      bottom: UILooks.pt(M.Briefing.padding), right: UILooks.pt(M.Briefing.padding))
        box.layer?.backgroundColor = M.Search.bg.cgColor
        box.layer?.borderColor = M.Briefing.border.cgColor
        box.layer?.borderWidth = DesignTokens.Stroke.hairline
        box.layer?.cornerRadius = UILooks.pt(M.Briefing.radius)
        return box
    }

    static func briefing(_ see: @escaping @MainActor () -> Void) -> NSView {
        // The mockup's line-height (1.5 × the size), as a fixed line: a multiple of the font's own
        // line made it taller than the drawing (measured 2026-11-17).
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = UILooks.pt(M.Briefing.fontSize * M.Briefing.lineHeight)
        style.maximumLineHeight = style.minimumLineHeight
        let font = UILooks.font(M.Briefing.fontSize)
        let text = NSMutableAttributedString(string: T("Each new agent here starts with a briefing of this. ", "Cada agente novo aqui começa com um briefing disto. "),
                                             attributes: [.font: font, .foregroundColor: M.Briefing.color, .paragraphStyle: style])
        text.append(NSAttributedString(string: T("See the briefing", "Ver o briefing"),
                                       attributes: [.font: font, .foregroundColor: DesignTokens.Color.textPrimary, .paragraphStyle: style]))
        let field = NSTextField(wrappingLabelWithString: "")
        // Not selectable: a click on the words must reach the box and open the briefing.
        field.isSelectable = false
        field.attributedStringValue = text
        let box = MemoryBox(views: [field], press: see)
        box.edgeInsets = NSEdgeInsets(top: UILooks.pt(M.Briefing.padding), left: UILooks.pt(M.Briefing.padding),
                                      bottom: UILooks.pt(M.Briefing.padding), right: UILooks.pt(M.Briefing.padding))
        box.layer?.borderColor = M.Briefing.border.cgColor
        box.layer?.borderWidth = DesignTokens.Stroke.hairline
        box.layer?.cornerRadius = UILooks.pt(M.Briefing.radius)
        box.setAccessibilityLabel(text.string)
        return box
    }

    private static func insets(_ edges: NSEdgeInsets) -> NSEdgeInsets {
        NSEdgeInsets(top: UILooks.pt(edges.top), left: UILooks.pt(edges.left), bottom: UILooks.pt(edges.bottom), right: UILooks.pt(edges.right))
    }
}

/// A box of the tab that may be pressed: the click runs what the page passes (a command by id).
@MainActor
final class MemoryBox: NSStackView {
    private var press: (@MainActor () -> Void)?

    convenience init(views: [NSView], press: (@MainActor () -> Void)?) {
        self.init(views: views)
        self.press = press
        wantsLayer = true
        if press != nil { setAccessibilityRole(.button) }
    }

    override func mouseDown(with event: NSEvent) { if press == nil { super.mouseDown(with: event) } }
    /// The first click of an inactive window presses too (2026-11-18).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { press != nil }
    override func mouseUp(with event: NSEvent) {
        guard let press, bounds.contains(convert(event.locationInWindow, from: nil)) else { return super.mouseUp(with: event) }
        press()
    }

    /// VoiceOver presses it as the click does.
    override func accessibilityPerformPress() -> Bool {
        guard let press else { return false }
        press()
        return true
    }

    override func resetCursorRects() {
        if press != nil { addCursorRect(bounds, cursor: .pointingHand) }
    }
}
