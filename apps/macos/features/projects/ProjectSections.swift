import AppKit
import Icons
import Strings
import UILooks

/// The sections inside a project's page (plan 34 C; docs/design/projects/proposta.html): they live
/// in the page, under its head, never in the bar.
public enum ProjectSection: String, CaseIterable, Sendable {
    case overview, sessions, memory, automations, settings

    var title: String {
        switch self {
        case .overview: T("Overview", "Visão geral")
        case .sessions: T("Sessions", "Sessões")
        case .memory: T("Memory", "Memória")
        case .automations: T("Automations", "Automações")
        case .settings: T("Settings", "Configurações")
        }
    }
}

/// A line of a section's list: a session or a memory page. `group` puts it under a title
/// ("RULES · WHAT EVERY AGENT GETS"); `tile`, the kind's glyph in its color; `noteLogo`, Claude's
/// logo before the note (the account).
public struct PageListItem: Equatable {
    public var id: String
    public var title: String
    public var note: String
    public var noteLogo: Bool
    public var tile: Icon?
    public var tint: NSColor?
    public var group: String?

    public init(id: String, title: String, note: String, noteLogo: Bool = false, tile: Icon? = nil, tint: NSColor? = nil, group: String? = nil) {
        self.id = id
        self.title = title
        self.note = note
        self.noteLogo = noteLogo
        self.tile = tile
        self.tint = tint
        self.group = group
    }
}

/// What shows beside the list for the chosen line, rendered (never the raw .md): a chip with the
/// kind, the title, a line under it, the text as headings, paragraphs and items, the tags, a list
/// of related lines and the buttons.
public struct PageDetail {
    public enum Block: Equatable { case heading(String), paragraph(String), item(String) }
    public struct Related { public var tile: Icon; public var tint: NSColor; public var text: String
        public init(tile: Icon, tint: NSColor, text: String) { self.tile = tile; self.tint = tint; self.text = text } }
    public struct Button { public var title: String; public var primary: Bool; public var danger: Bool; public var action: @MainActor () -> Void
        public init(_ title: String, primary: Bool = false, danger: Bool = false, action: @escaping @MainActor () -> Void) {
            self.title = title; self.primary = primary; self.danger = danger; self.action = action } }

    public var chip: (text: String, tint: NSColor)?
    public var title: String
    public var meta: String
    public var metaLogo: Bool
    public var blocks: [Block]
    public var tags: [String]
    public var relatedTitle: String
    public var related: [Related]
    public var buttons: [Button]

    public init(chip: (text: String, tint: NSColor)? = nil, title: String, meta: String, metaLogo: Bool = false, blocks: [Block] = [],
                tags: [String] = [], relatedTitle: String = "", related: [Related] = [], buttons: [Button] = []) {
        self.chip = chip
        self.title = title
        self.meta = meta
        self.metaLogo = metaLogo
        self.blocks = blocks
        self.tags = tags
        self.relatedTitle = relatedTitle
        self.related = related
        self.buttons = buttons
    }
}

/// The segmented control of the sections (the proposal's `.seg`): a rounded tray, the chosen one
/// raised.
@MainActor
final class SectionSwitch: NSStackView {
    var onChoose: ((ProjectSection) -> Void)?

    func show(_ chosen: ProjectSection) {
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        wantsLayer = true
        layer?.backgroundColor = DesignTokens.Color.bgCard.cgColor
        layer?.borderColor = DesignTokens.Color.lineDefault.cgColor
        layer?.borderWidth = DesignTokens.Stroke.hairline
        layer?.cornerRadius = UILooks.pt(DesignTokens.Radius.item)
        spacing = UILooks.pt(2)
        edgeInsets = NSEdgeInsets(top: UILooks.pt(3), left: UILooks.pt(3), bottom: UILooks.pt(3), right: UILooks.pt(3))
        for section in ProjectSection.allCases {
            let on = section == chosen
            let label = pageLabel(section.title, size: DesignTokens.FontSize.panel, color: on ? DesignTokens.Color.textPrimary : DesignTokens.Color.textSecondary,
                                  weight: on ? .semibold : .regular)
            let item = PageBox()
            item.wantsLayer = true
            item.layer?.cornerRadius = UILooks.pt(DesignTokens.Radius.control)
            item.layer?.backgroundColor = on ? DesignTokens.Color.bgSelected.cgColor : nil
            item.hold(label, padding: NSEdgeInsets(top: 5, left: 12, bottom: 5, right: 12))
            item.onPress = { [weak self] in self?.onChoose?(section) }
            item.setAccessibilityElement(true)
            item.setAccessibilityRole(.radioButton)
            item.setAccessibilityLabel(section.title)
            addArrangedSubview(item)
        }
    }
}
