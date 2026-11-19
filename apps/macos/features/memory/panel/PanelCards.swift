import AppKit
import Menus
import Strings
import UILooks

/// One of the five numbers on top (components.memoryPanel.stat): the label over the value; the click
/// orders the cards by it (upstream's links). Upstream's note under it goes to the help (its tip).
@MainActor
final class PanelStat: PanelPress {
    let title: String
    let value: NSTextField

    init(_ title: String, value text: String, amber: Bool, note: String) {
        self.title = title
        value = PanelText.line(text, size: MP.Stat.Value.fontSize, color: amber ? MP.Stat.Value.open : MP.Stat.Value.color,
                               weight: MP.Stat.Value.weight)
        super.init(frame: .zero)
        box(bg: MP.Stat.bg, border: MP.Stat.border, radius: MP.Stat.radius)
        let label = PanelText.line(title, size: MP.Stat.Label.fontSize, color: MP.Stat.Label.color)
        hold(PanelText.column([label, value], gap: MP.Stat.gap), padding: MP.Stat.padding)
        toolTip = note
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title + " " + text)
        setAccessibilityHelp(note)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelStat is created in code") }
}

/// What a project's card can do; each is a command's work (ADR 0005).
@MainActor
struct PanelCardActions {
    var open: (PanelProject) -> Void = { _ in }
    var agents: (PanelProject) -> Void = { _ in }
    /// Nil: no Cadex project has this one's folder (_global, scratch), so no "Abrir no Cadex".
    var openInCadex: ((PanelProject) -> Void)?
}

/// A project's card (components.memoryPanel.projectCard): the mark, the name and its agents, four
/// numbers, and at the foot the last capture, "Agentes ↗" and "Abrir no Cadex". The click opens the
/// project's memory; the right click has the same as the foot.
@MainActor
final class PanelCard: PanelPress {
    typealias C = MP.ProjectCard
    let project: PanelProject
    var chosen = false { didSet { paint() } }
    private let actions: PanelCardActions

    init(_ project: PanelProject, now: Date, actions: PanelCardActions) {
        self.project = project
        self.actions = actions
        super.init(frame: .zero)
        let head = PanelText.row([avatar(), names()], gap: MP.Nav.Row.gap)
        let numbers = numberGrid()
        let foot = footLine(now: now)
        let column = PanelText.column([head, numbers, foot], gap: C.gap)
        for part in [numbers, foot] { part.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        hold(column, padding: C.padding)
        onPress = { actions.open(project) }
        entriesFor = { [weak self] in self?.entries() ?? [] }
        onHover = { [weak self] on in self?.layer?.borderColor = (on || self?.chosen == true ? MP.Field.Focus.border : C.border).cgColor }
        paint()
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(project.name)
        setAccessibilityHelp(T("\(project.sessions) sessions, \(project.pages) pages", "\(project.sessions) sessões, \(project.pages) páginas"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelCard is created in code") }

    private func paint() {
        box(bg: C.bg, border: chosen ? MP.Field.Focus.border : C.border, radius: C.radius)
    }

    func entries() -> [MenuEntry] {
        var list = [MenuEntry(T("Open Memory", "Abrir a memória"), icon: .brain) { [actions, project] in actions.open(project) },
                    MenuEntry(T("Agents", "Agentes"), icon: .arrowSquareOut) { [actions, project] in actions.agents(project) }]
        if let open = actions.openInCadex {
            list.append(MenuEntry(T("Open in Cadex", "Abrir no Cadex"), icon: .folderOpen, shortcut: "⌘O") { [project] in open(project) })
        }
        return list
    }

    var canOpenInCadex: Bool { actions.openInCadex != nil }
    func openInCadex() { actions.openInCadex?(project) }
    func openMemory() { actions.open(project) }

    private func avatar() -> NSView {
        let box = FrameBox()
        box.box(bg: C.Avatar.bg, border: nil, radius: C.Avatar.radius)
        let mark = PanelText.line(PanelWords.mark(project.name), size: C.Avatar.fontSize, color: DesignTokens.Color.textPrimary, weight: C.Avatar.weight)
        mark.alignment = .center
        mark.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(mark)
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: UILooks.pt(C.Avatar.size)),
            box.heightAnchor.constraint(equalToConstant: UILooks.pt(C.Avatar.size)),
            mark.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        return box
    }

    private func names() -> NSView {
        let name = PanelText.line(project.name, size: DesignTokens.FontSize.body, color: DesignTokens.Color.textPrimary,
                                  weight: DesignTokens.FontWeight.semibold)
        var top: [NSView] = [name]
        if project.inbox > 0 { top.append(PanelText.chip(T("\(project.inbox) inbox", "\(project.inbox) caixa de entrada"), amber: true)) }
        let agents = PanelText.line(PanelWords.agents(project.agents), size: C.Foot.fontSize, color: C.Foot.color)
        return PanelText.column([PanelText.row(top, gap: MP.Chip.gap), agents], gap: MP.Chip.padding.top)
    }

    private func numberGrid() -> NSView {
        let cells = [(T("Sessions", "Sessões"), project.sessions), (T("Captured events", "Eventos capturados"), project.events),
                     (T("Compiled pages", "Páginas compiladas"), project.pages), (T("Open sessions", "Sessões abertas"), project.open)]
            .map { title, value in
                PanelText.column([PanelText.line(title, size: C.Number.Label.fontSize, color: C.Number.Label.color),
                                  PanelText.line(PanelWords.number(value), size: C.Number.Value.fontSize, color: DesignTokens.Color.textPrimary,
                                                 weight: C.Number.Value.weight)], gap: MP.Chip.padding.top)
            }
        let rows = [Array(cells[0..<2]), Array(cells[2..<4])].map { pair -> NSStackView in
            let row = NSStackView(views: pair)
            row.distribution = .fillEqually
            row.spacing = UILooks.pt(C.Number.columnGap)
            return row
        }
        let grid = PanelText.column(rows, gap: C.Number.rowGap)
        for row in rows { row.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true }
        return grid
    }

    private func footLine(now: Date) -> NSView {
        // The time alone ("há 9 horas"), the whole line in the tooltip: with both links, "Última
        // captura: há 9 horas" was cut to "Última captura:…" (phase C, 2026-11-19; the owner's short copy).
        let whole = PanelWords.lastCapture(project.lastActivity, now: now)
        let last = PanelText.line(project.lastActivity.map { PanelWords.ago($0, now: now) } ?? T("No capture", "Nenhuma captura"),
                                  size: C.Foot.fontSize, color: C.Foot.color)
        last.setContentCompressionResistancePriority(.required, for: .horizontal)
        last.toolTip = whole
        last.setAccessibilityLabel(whole)
        var views: [NSView] = [last, PanelText.spring(),
                               PanelLink(T("Agents ↗", "Agentes ↗"), size: C.Foot.fontSize) { [actions, project] in actions.agents(project) }]
        if let open = actions.openInCadex {
            views.append(PanelLink(T("Open in Cadex", "Abrir no Cadex"), size: C.Foot.fontSize) { [project] in open(project) })
        }
        let row = PanelText.row(views, gap: C.Foot.gap)
        let rule = NSView()
        rule.wantsLayer = true
        rule.layer?.backgroundColor = C.Foot.border.cgColor
        rule.heightAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline).isActive = true
        let foot = PanelText.column([rule, row], gap: C.Foot.paddingTop)
        for part in [rule, row] { part.widthAnchor.constraint(equalTo: foot.widthAnchor).isActive = true }
        return foot
    }

    /// For tests: the foot's links.
    var footLinks: [String] {
        func links(_ v: NSView) -> [String] { ((v as? PanelLink).map { [$0.label.stringValue] } ?? []) + v.subviews.flatMap(links) }
        return links(self)
    }
}
