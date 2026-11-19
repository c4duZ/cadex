import AppKit
import Menus
import StateGlyph
import Strings
import Tabs
import UILooks

/// One project's card on the Projects page (plan 34 B; docs/design/projects/proposta.html,
/// "Projetos"): its name, where it is, how many tasks, sessions and memories, and what is going on.
public struct ProjectCard: Equatable {
    public var folder: String
    public var name: String
    /// "~/Cadu/Trabalho/bkdg/bkdg-center · dev/center".
    public var place: String
    public var tasks: Int
    public var sessions: Int
    public var memories: Int
    /// "agent working · 8 min", "1 waiting for you", "last session yesterday".
    public var status: String
    /// The status's dot: working (green in the proposal), needs (amber), or none.
    public var state: GlyphState?
    /// The project's tile beside the name (plan 36 B); nil: the name alone.
    public var picture: ProjectPicture?

    public init(folder: String, name: String, place: String, tasks: Int, sessions: Int, memories: Int, status: String, state: GlyphState?) {
        self.folder = folder
        self.name = name
        self.place = place
        self.tasks = tasks
        self.sessions = sessions
        self.memories = memories
        self.status = status
        self.state = state
    }
}

/// What the Projects page asks the app.
@MainActor
public struct ProjectsListActions {
    public var open: (String) -> Void = { _ in }
    /// A card's right click: the app's menu for that project (the rail's).
    public var menu: (String) -> [MenuEntry] = { _ in [] }
    public var add: () -> Void = {}
    public var load: (@escaping @MainActor ([ProjectCard]) -> Void) -> Void = { _ in }
    public init() {}
}

/// The Projects page: "Projects", how many and that each one's memory is shared by every account,
/// Add project, and a card per project in three columns (two, one, as the page narrows); a click
/// opens the project's page. A page (isPage): under the bar, never in it.
@MainActor
public final class ProjectsListDocument: TabDocument {
    public static let identity = "cadex:projects"
    private let actions: ProjectsListActions
    private let page = FlippedPage()
    public var view: NSView { page }
    public var title: String { T("Projects", "Projetos") }
    public var identity: String { Self.identity }
    public var hasUnsavedChanges: Bool { false }
    public var onChange: (() -> Void)?
    public var isPage: Bool { true }

    public init(actions: ProjectsListActions) {
        self.actions = actions
        page.wantsLayer = true
        page.layer?.backgroundColor = DesignTokens.Color.bgWindow.cgColor
        reload()
    }

    public func focus() { reload() }
    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }
    public func close() {}

    public func reload() {
        actions.load { [weak self] cards in self?.show(cards) }
    }

    func show(_ cards: [ProjectCard]) {
        page.show(head: head(cards), body: grid(cards))
    }

    private func head(_ cards: [ProjectCard]) -> NSView {
        let count = cards.count == 1 ? T("1 project", "1 projeto") : T("\(cards.count) projects", "\(cards.count) projetos")
        let words = vertical([pageLabel(title, size: PP.Title.fontSize, color: DesignTokens.Color.textPrimary, weight: PP.Title.weight, tracking: PP.Title.tracking),
                              pageLabel(count + T(" · each one's memory is shared by every account", " · a memória de cada um é dividida por todas as contas"),
                                        size: DesignTokens.FontSize.body, color: PP.Head.meta)], gap: PP.Head.titleGap)
        words.setHuggingPriority(.init(1), for: .horizontal)
        words.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let add = DesignButton.make("+  " + T("Add project", "Adicionar projeto"), .primary) { [weak self] in self?.actions.add() }
        let row = NSStackView(views: [words, add])
        row.distribution = .fill
        row.alignment = .bottom
        row.spacing = UILooks.pt(PP.Head.gap)
        page.head = row
        return row
    }

    private func grid(_ cards: [ProjectCard]) -> NSView {
        let minimum = UILooks.pt(PP.Stat.minWidth) * 1.4
        return PageFlow(cards.map(card), mode: .grid { width in width >= minimum * 3 ? 3 : width >= minimum * 2 ? 2 : 1 }, gap: PP.Stat.gridGap)
    }

    private func card(_ project: ProjectCard) -> NSView {
        typealias S = PP.Stat
        let box = PageBox()
        box.box(bg: S.bg, border: S.border, radius: S.radius)
        box.onPress = { [weak self] in self?.actions.open(project.folder) }
        box.rightMenu = { [weak self] in self?.actions.menu(project.folder) ?? [] }
        let name = pageLabel(project.name, size: DesignTokens.FontSize.prompt, color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.bold)
        let place = pageLabel(project.place, size: DesignTokens.FontSize.small, color: DesignTokens.Color.textTertiary)
        // Cut in the middle: the folder's name and the branch are the end of the line (UX audit, 2026-11-18).
        place.lineBreakMode = .byTruncatingMiddle
        place.toolTip = project.place
        let stats = NSTextField(labelWithString: "")
        stats.attributedStringValue = Self.stats(project)
        var lines: [NSView] = [name, place, stats]
        // The line the stats come after: the place, or the head that holds it beside the tile.
        var abovePlace: NSView = place
        if let picture = project.picture {
            // The tile beside the name and the place, as the rail shows the project.
            let words = vertical([name, place], gap: PP.Head.titleGap)
            let head = NSStackView(views: [ProjectPreview.of(picture, name: project.name), words])
            head.alignment = .centerY
            head.spacing = UILooks.pt(PP.Head.gap)
            lines = [head, stats]
            abovePlace = head
        }
        let status = pageLabel(project.status, size: DesignTokens.FontSize.small,
                               color: project.state == .needs ? DesignTokens.Color.stateNeeds : DesignTokens.Color.textTertiary)
        if let state = project.state {
            let glyph = StateGlyphView(size: DesignTokens.Pane.Header.glyph, state: state)
            glyph.widthAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Pane.Header.glyph)).isActive = true
            glyph.heightAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Pane.Header.glyph)).isActive = true
            let row = NSStackView(views: [glyph, status])
            row.spacing = UILooks.pt(PP.Row.textGap * 2)
            lines.append(row)
        } else {
            lines.append(status)
        }
        let column = vertical(lines, gap: PP.Row.textGap)
        column.setCustomSpacing(UILooks.pt(PP.Stat.gap * 3), after: abovePlace)
        column.setCustomSpacing(UILooks.pt(PP.Stat.gap * 3), after: stats)
        box.hold(column, padding: S.padding)
        box.setAccessibilityElement(true)
        box.setAccessibilityRole(.button)
        box.setAccessibilityLabel(project.name + ", " + project.status)
        return box
    }

    /// "2 tasks   29 sessions   34 memories", the numbers in the text's color and bold.
    static func stats(_ project: ProjectCard) -> NSAttributedString {
        let text = NSMutableAttributedString()
        let parts = [(project.tasks, T("tasks", "tarefas"), T("task", "tarefa")),
                     (project.sessions, T("sessions", "sessões"), T("session", "sessão")),
                     (project.memories, T("memories", "memórias"), T("memory", "memória"))]
        for (index, part) in parts.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "    ")) }
            text.append(NSAttributedString(string: "\(part.0)", attributes: [
                .font: UILooks.font(DesignTokens.FontSize.meta, weight: .semibold), .foregroundColor: DesignTokens.Color.textPrimary,
            ]))
            text.append(NSAttributedString(string: " " + (part.0 == 1 ? part.2 : part.1), attributes: [
                .font: UILooks.font(DesignTokens.FontSize.meta), .foregroundColor: DesignTokens.Color.textSecondary,
            ]))
        }
        return text
    }
}
