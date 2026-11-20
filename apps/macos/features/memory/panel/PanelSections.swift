import AppKit
import Icons
import Strings
import UILooks

/// The panel's nine destinations, upstream's left menu in its groups and order
/// (MemorySidebar.dc.html; screens-memory.md, MemorySidebar).
public enum MemoryPanelSection: String, CaseIterable, Sendable {
    case projects, inbox, workstreams, search, graph, review, health, docs, changelog

    public var title: String {
        switch self {
        case .projects: T("Projects", "Projetos")
        case .inbox: T("Inbox", "Caixa de entrada")
        case .workstreams: "Workstreams"
        case .search: T("Search Memory", "Pesquisar na memória")
        case .graph: T("Knowledge Graph", "Grafo de conhecimento")
        case .review: T("Learning Review", "Revisão de aprendizado")
        case .health: T("Server Health", "Saúde do servidor")
        case .docs: T("Documentation", "Documentação")
        case .changelog: T("Changelog", "Histórico de alterações")
        }
    }

    public var icon: Icon {
        switch self {
        case .projects: .folderSimple
        case .inbox: .envelopeSimple
        case .workstreams: .gitBranch
        case .search: .magnifyingGlass
        case .graph: .graph
        case .review: .shieldCheck
        case .health: .pulse
        case .docs: .fileText
        case .changelog: .clockCounterClockwise
        }
    }

    /// The groups' captions with their sections.
    public static var groups: [(caption: String, sections: [MemoryPanelSection])] {
        [(T("WORKSPACE", "ESPAÇO DE TRABALHO"), [.projects, .inbox, .workstreams, .search, .graph]),
         (T("OBSERVE AND IMPROVE", "OBSERVAR E MELHORAR"), [.review, .health]),
         (T("RESOURCES", "RECURSOS"), [.docs, .changelog])]
    }

    /// Every section is drawn (plan 40 C to G); kept for a section upstream adds before Cadex draws it.
    public var isBuilt: Bool { true }
}

/// The sidebar's content while the Memória page shows (components.memoryPanel.nav): the search
/// field, then the three groups. The sidebar puts it under "‹ Trabalho"; a click says which section
/// (the app runs memory.show-panel with it), Enter in the field says what to search.
@MainActor
public final class MemoryPanelNav: NSView {
    typealias N = DesignTokens.MemoryPanel.Nav
    public var onPick: ((MemoryPanelSection) -> Void)?
    public var onSearch: ((String) -> Void)?
    private let field = NSTextField()
    private var rows: [MemoryPanelSection: MemoryNavRow] = [:]
    public private(set) var section: MemoryPanelSection = .projects

    public init() {
        super.init(frame: .zero)
        var views: [NSView] = [searchBox()]
        for (index, group) in MemoryPanelSection.groups.enumerated() {
            views.append(caption(group.caption, first: index == 0))
            for section in group.sections {
                let row = MemoryNavRow(section)
                row.onPress = { [weak self] in self?.onPick?(section) }
                rows[section] = row
                views.append(row)
            }
        }
        let stack = PanelText.column(views, gap: 0)
        stack.setCustomSpacing(UILooks.pt(N.Search.margin.bottom), after: views[0])
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
        for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        select(.projects)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(T("Memory sections", "Seções da memória"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("MemoryPanelNav is created in code") }

    /// The open section's line lit (inside a project, Projetos stays lit, as upstream).
    public func select(_ next: MemoryPanelSection) {
        section = next
        for (key, row) in rows { row.selected = key == next }
    }

    /// The messages waiting, at the right of Caixa de entrada; none hides it.
    public func setInbox(_ count: Int) { rows[.inbox]?.count = count }

    /// "Pesquisar em cadex" inside a project; nil, "Pesquisar na memória".
    public func setScope(_ project: String?) {
        let hint = project.map { T("Search in ", "Pesquisar em ") + $0 } ?? T("Search memory", "Pesquisar na memória")
        field.placeholderAttributedString = NSAttributedString(string: hint, attributes: [
            .font: UILooks.font(N.Search.fontSize), .foregroundColor: N.Search.color,
        ])
    }

    private func searchBox() -> NSView {
        let box = FrameBox()
        box.box(bg: N.Search.bg, border: N.Search.border, radius: N.Search.radius)
        let glass = NSImageView(image: Icon.magnifyingGlass.image(size: UILooks.pt(N.Search.icon)))
        glass.contentTintColor = N.Search.color
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = UILooks.font(N.Search.fontSize)
        field.textColor = DesignTokens.Color.textPrimary
        field.target = self
        field.action = #selector(searched)
        field.setAccessibilityLabel(T("Search memory", "Pesquisar na memória"))
        setScope(nil)
        box.hold(PanelText.row([glass, field], gap: N.Search.gap), padding: N.Search.padding)
        box.heightAnchor.constraint(equalToConstant: UILooks.rowHeight(N.Search.height)).isActive = true
        let holder = NSStackView(views: [box])
        holder.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(N.Search.margin.left), bottom: 0, right: UILooks.pt(N.Search.margin.right))
        box.widthAnchor.constraint(equalTo: holder.widthAnchor, constant: -UILooks.pt(N.Search.margin.left) - UILooks.pt(N.Search.margin.right)).isActive = true
        return holder
    }

    @objc private func searched() {
        let words = field.stringValue.trimmingCharacters(in: .whitespaces)
        if !words.isEmpty { onSearch?(words) }
    }

    private func caption(_ text: String, first: Bool) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: UILooks.font(N.Group.fontSize, weight: N.Group.weight), .foregroundColor: N.Group.color,
            .kern: UILooks.pt(N.Group.fontSize) * N.Group.tracking,
        ])
        let box = FrameBox()
        var pad = N.Group.padding
        if !first { pad.top = N.Group.marginTop }
        box.hold(label, padding: pad)
        return box
    }

    /// For tests: the lines in order, the lit one, the inbox count shown.
    var lineTitles: [String] { MemoryPanelSection.allCases.compactMap { rows[$0]?.title } }
    var litSection: MemoryPanelSection? { rows.first { $0.value.selected }?.key }
    var inboxSaid: String { rows[.inbox]?.countSaid ?? "" }
    func press(_ section: MemoryPanelSection) { rows[section]?.onPress?() }
    func search(_ words: String) {
        field.stringValue = words
        searched()
    }
}

/// A section's line (components.memoryPanel.nav.row): the icon, the title and, on the inbox, the
/// count; lit with the row's selected fill.
@MainActor
final class MemoryNavRow: PanelPress {
    typealias R = DesignTokens.MemoryPanel.Nav.Row
    let title: String
    private let label: NSTextField
    private let glyph: NSImageView
    private let countLabel = NSTextField(labelWithString: "")
    var selected = false { didSet { paint() } }
    var count = 0 { didSet { countLabel.stringValue = count > 0 ? PanelWords.number(count) : ""; countLabel.isHidden = count == 0 } }
    var countSaid: String { countLabel.isHidden ? "" : countLabel.stringValue }

    init(_ section: MemoryPanelSection) {
        title = section.title
        label = PanelText.line(section.title, size: R.fontSize, color: R.color)
        glyph = NSImageView(image: section.icon.fittedImage(size: UILooks.pt(R.icon)))
        super.init(frame: .zero)
        countLabel.font = UILooks.font(DesignTokens.MemoryPanel.Nav.FootItem.Version.fontSize)
        countLabel.textColor = DesignTokens.MemoryPanel.Nav.FootItem.Version.color
        countLabel.isHidden = true
        hold(PanelText.row([glyph, label, PanelText.spring(), countLabel], gap: R.gap), padding: R.padding)
        heightAnchor.constraint(equalToConstant: UILooks.rowHeight(R.height)).isActive = true
        onHover = { [weak self] on in
            guard let self, !self.selected else { return }
            self.layer?.backgroundColor = on ? R.Selected.bg.cgColor : nil
        }
        paint()
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(section.title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("MemoryNavRow is created in code") }

    private func paint() {
        box(bg: selected ? R.Selected.bg : nil, border: nil, radius: R.radius)
        label.textColor = selected ? R.Selected.color : R.color
        label.font = UILooks.font(R.fontSize, weight: selected ? R.Selected.weight : .regular)
        glyph.contentTintColor = selected ? R.Selected.color : R.color
        setAccessibilityValue(selected ? T("selected", "escolhida") : nil)
    }
}
