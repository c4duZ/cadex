import AppKit
import Icons
import Menus
import Strings
import UILooks

/// The rail (docs/adr/0038-rail-and-side-column.md; the Rail mockup): the narrow strip at the
/// window's left edge with the projects on top, the "+" that adds one, and at the foot what is about
/// every project (Projects, Automations). The app gathers the projects (`RailProject`); a click on a
/// tile comes back by `onPick`, and every button runs a command by its id (ADR 0005).
@MainActor
public final class RailView: NSView {
    typealias R = DesignTokens.Rail
    /// A project's tile was clicked: its folder.
    public var onPick: ((String) -> Void)?
    /// A right click on a tile: the menu's entries for that project (each runs a command).
    public var menuFor: ((String) -> [MenuEntry])?
    /// An image file dropped on a tile: the project's folder and the file.
    public var onDropImage: ((String, URL) -> Void)?
    /// The foot's page that shows (lit), or nil.
    public var footLit: RailFoot? { didSet { if footLit != oldValue { lightFoot() } } }
    private let run: (String) -> Void
    /// The projects and the "+", in `projectsScroll`: many projects scroll there, the pages and the
    /// foot stay put (the owner, 2026-11-18).
    let top = NSStackView()
    private let projectsScroll = NSScrollView()
    /// The pages' line and icons, under the projects.
    let pagesStack = NSStackView()
    private let foot = NSStackView()
    private var shown: (projects: [RailProject], chosen: String?)?
    var tiles: [RailTile] = []
    private let add: RailButton
    private let pagesLine = NSView()
    var pageButtons: [(RailPage, RailButton)] = []
    /// A tile dragged to a new place (plan 36 phase E): its folder, the tiles' folders in the new
    /// order, and whether it is now pinned (above the line).
    public var onMove: ((String, [String], Bool) -> Void)?
    /// The page icons dragged into a new order: their ids.
    public var onMovePages: (([String]) -> Void)?
    /// The tile or icon being dragged now.
    var dragged: NSView?
    /// The command that folds the column: the lit page's click runs it (as VS Code's activity bar).
    public var toggleCommand = "view.toggle-sidebar"
    /// The page the column shows (nil: closed): its icon lit.
    public var pageLit: String? { didSet { if pageLit != oldValue { lightPages() } } }
    private let footButtons: [(RailFoot, RailButton)]

    public init(run: @escaping (String) -> Void) {
        self.run = run
        add = RailButton(command: "project.create", icon: .plus, tip: T("New Project…", "Novo projeto…"))
        footButtons = [
            (.projects, RailButton(command: "project.show-all", icon: .squaresFour, tip: T("Projects", "Projetos"))),
            (.automations, RailButton(command: "orchestration.show-automations", icon: .clock, tip: T("Automations", "Automações"))),
            (.remote, RailButton(command: "remote.show", icon: .globe, tip: T("Remote Machines", "Máquinas remotas"))),
        ]
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = R.bg.cgColor
        add.onPress = { [weak self] in self?.run("project.create") }
        for (_, button) in footButtons {
            let command = button.command
            button.onPress = { [weak self] in self?.run(command) }
        }
        for stack in [top, foot, pagesStack] {
            stack.orientation = .vertical
            stack.alignment = .centerX
            stack.spacing = UILooks.pt(R.gap)
        }
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = R.Separator.color.cgColor
        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = R.borderRight.cgColor
        foot.addArrangedSubview(separator)
        foot.setCustomSpacing(UILooks.pt(R.Separator.margin) + UILooks.pt(R.gap), after: separator)
        for (_, button) in footButtons { foot.addArrangedSubview(button) }
        // Observers do not run in init: hidden by hand until the app says there is a host.
        footButtons.first { $0.0 == .remote }?.1.isHidden = true
        top.addArrangedSubview(add)
        pagesLine.wantsLayer = true
        pagesLine.layer?.backgroundColor = R.Separator.color.cgColor
        pagesLine.translatesAutoresizingMaskIntoConstraints = false
        pagesLine.isHidden = true
        pagesStack.addArrangedSubview(pagesLine)
        let clip = RailClip()
        clip.drawsBackground = false
        projectsScroll.contentView = clip
        projectsScroll.documentView = top
        projectsScroll.drawsBackground = false
        projectsScroll.hasVerticalScroller = false
        projectsScroll.verticalScrollElasticity = .none
        top.translatesAutoresizingMaskIntoConstraints = false
        for view in [projectsScroll, pagesStack, foot, border] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        // As tall as the projects when they fit; shorter, and scrolling, when the pages would meet the foot.
        let fit = projectsScroll.heightAnchor.constraint(equalTo: top.heightAnchor)
        // Under the window's own (500): stronger, the projects held the window open and nothing scrolled.
        fit.priority = .defaultLow
        let hairline = DesignTokens.Stroke.hairline
        NSLayoutConstraint.activate([
            projectsScroll.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(R.padding.top)),
            projectsScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            projectsScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            fit,
            top.topAnchor.constraint(equalTo: clip.topAnchor),
            top.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            top.widthAnchor.constraint(equalTo: clip.widthAnchor),
            pagesStack.topAnchor.constraint(equalTo: projectsScroll.bottomAnchor, constant: UILooks.pt(R.gap)),
            pagesStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            pagesStack.bottomAnchor.constraint(lessThanOrEqualTo: foot.topAnchor, constant: -UILooks.pt(R.gap)),
            foot.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -UILooks.pt(R.padding.bottom)),
            foot.centerXAnchor.constraint(equalTo: centerXAnchor),
            separator.widthAnchor.constraint(equalToConstant: UILooks.pt(R.Separator.width)),
            pagesLine.widthAnchor.constraint(equalToConstant: UILooks.pt(R.Separator.width)),
            pagesLine.heightAnchor.constraint(equalToConstant: hairline),
            separator.heightAnchor.constraint(equalToConstant: hairline),
            border.topAnchor.constraint(equalTo: topAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.widthAnchor.constraint(equalToConstant: hairline),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("RailView is created in code") }

    override public var mouseDownCanMoveWindow: Bool { false }

    /// The projects and the chosen one (a folder); redraws only when they changed.
    public func show(_ projects: [RailProject], chosen: String?) {
        if let shown, shown.projects == projects, shown.chosen == chosen { return }
        shown = (projects, chosen)
        tiles.forEach { $0.removeFromSuperview() }
        groupLine.removeFromSuperview()
        tiles = projects.map { project in
            let tile = RailTile(project: project, chosen: project.id == chosen)
            tile.onPress = { [weak self] in self?.onPick?(project.id) }
            tile.onMenu = { [weak self, weak tile] event in
                guard let self, let tile, let entries = self.menuFor?(project.id), !entries.isEmpty else { return }
                PopupMenu.show(entries, at: tile.convert(event.locationInWindow, from: nil), in: tile)
            }
            tile.onDropImage = { [weak self] url in self?.onDropImage?(project.id, url) }
            tile.onDrag = { [weak self, weak tile] event, ended in
                guard let self, let tile else { return }
                ended ? self.dragEnded(tile, .project) : self.dragMoved(tile, .project, event)
            }
            return tile
        }
        for (index, tile) in tiles.enumerated() { top.insertArrangedSubview(tile, at: index) }
        // The pinned ones first, then a line, then the open ones not pinned (the Dock's two parts).
        if let first = tiles.firstIndex(where: { !$0.project.pinned }), first > 0 {
            top.insertArrangedSubview(groupLine, at: first)
        }
    }

    /// Between the pinned projects and the others.
    lazy var groupLine: NSView = {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = R.Separator.color.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: UILooks.pt(R.Separator.width)).isActive = true
        line.heightAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline).isActive = true
        return line
    }()

    var groupLineShown: Bool { groupLine.superview != nil }

    /// The side column's pages, under the projects and the "+", after a line. A click opens the
    /// column on the page; on the lit one, folds it.
    public func setPages(_ pages: [RailPage]) {
        pageButtons.forEach { $0.1.removeFromSuperview() }
        pageButtons = pages.map { page in
            let button = RailButton(command: page.command, icon: page.icon, tip: page.title)
            button.onPress = { [weak self] in
                guard let self else { return }
                self.run(self.pageLit == page.id ? self.toggleCommand : page.command)
            }
            button.onDrag = { [weak self, weak button] event, ended in
                guard let self, let button else { return }
                ended ? self.dragEnded(button, .page) : self.dragMoved(button, .page, event)
            }
            return (page, button)
        }
        for (_, button) in pageButtons { pagesStack.addArrangedSubview(button) }
        pagesLine.isHidden = pages.isEmpty
        pagesStack.setCustomSpacing(UILooks.pt(R.Separator.margin) + UILooks.pt(R.gap), after: pagesLine)
        lightPages()
    }

    private func lightPages() {
        for (page, button) in pageButtons { button.lit = page.id == pageLit }
    }

    var pageCommands: [String] { pageButtons.map(\.1.command) }
    var litPage: String? { pageButtons.first(where: \.1.lit)?.0.id }
    func pressPage(_ index: Int) { pageButtons[index].1.onPress?() }

    private func lightFoot() {
        for (page, button) in footButtons { button.lit = page == footLit }
    }

    /// Remote at the foot: only with some SSH host or tailnet machine (ADR 0038).
    public var remoteShown = false {
        didSet { footButtons.first { $0.0 == .remote }?.1.isHidden = !remoteShown }
    }

    /// For tests: the tiles' folders, the chosen one, the foot's commands and what is lit.
    var tileIDs: [String] { tiles.map(\.project.id) }
    var chosenID: String? { tiles.first(where: \.chosen)?.project.id }
    var footCommands: [String] { footButtons.filter { !$0.1.isHidden }.map(\.1.command) }
    var litCommands: [String] { footButtons.filter(\.1.lit).map(\.1.command) }
}

/// The projects' clip: laid from the top, so the first project sits under the padding.
private final class RailClip: NSClipView {
    override var isFlipped: Bool { true }
}
