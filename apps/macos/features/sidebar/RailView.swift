import AppKit
import Icons
import Menus
import Strings
import UILooks

/// The narrow window's strip (docs/adr/0039-sidebar-with-work-and-files.md, plan 38 G; the rail of
/// ADR 0038 before it): the requests' amber box on top, the projects' squares, and at the foot Files
/// (the sidebar over the center) and the board. The app gathers the projects (`RailProject`); a
/// click on a tile comes back by `onPick`, and every button runs a command by its id (ADR 0005).
@MainActor
public final class RailView: NSView {
    typealias R = DesignTokens.Rail
    /// A project's tile was clicked: its folder.
    public var onPick: ((String) -> Void)?
    /// A right click on a tile: the menu's entries for that project (each runs a command).
    public var menuFor: ((String) -> [MenuEntry])?
    /// An image file dropped on a tile: the project's folder and the file.
    public var onDropImage: ((String, URL) -> Void)?
    private let run: (String) -> Void
    /// The requests' box and the projects, in `projectsScroll`: many projects scroll there, the
    /// foot stays put (the owner, 2026-11-18).
    let top = NSStackView()
    private let projectsScroll = NSScrollView()
    private let foot = NSStackView()
    private var shown: (projects: [RailProject], chosen: String?)?
    var tiles: [RailTile] = []
    /// A tile dragged to a new place (plan 36 phase E): its folder, the tiles' folders in the new
    /// order, and whether it is now pinned (above the line).
    public var onMove: ((String, [String], Bool) -> Void)?
    /// The tile being dragged now.
    var dragged: NSView?
    private let footButtons: [RailButton]
    /// The requests, as an amber box with their number on top of the strip (plan 38 G).
    private let asking = RailAsking()
    public var requests = 0 {
        didSet {
            asking.say(requests)
            asking.isHidden = requests == 0
        }
    }

    public init(run: @escaping (String) -> Void) {
        self.run = run
        footButtons = [
            RailButton(command: "sidebar.show-files", icon: .folder, tip: T("Files", "Arquivos")),
            RailButton(command: "view.board", icon: .kanban, tip: T("Board", "Quadro")),
        ]
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = R.bg.cgColor
        asking.onPress = { [weak self] in self?.run("agents.go-to-request") }
        asking.isHidden = true
        for button in footButtons {
            let command = button.command
            button.onPress = { [weak self] in self?.run(command) }
        }
        for stack in [top, foot] {
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
        footButtons.forEach(foot.addArrangedSubview)
        top.addArrangedSubview(asking)
        let clip = RailClip()
        clip.drawsBackground = false
        projectsScroll.contentView = clip
        projectsScroll.documentView = top
        projectsScroll.drawsBackground = false
        projectsScroll.hasVerticalScroller = false
        projectsScroll.verticalScrollElasticity = .none
        top.translatesAutoresizingMaskIntoConstraints = false
        for view in [projectsScroll, foot, border] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        // As tall as the projects when they fit; shorter, and scrolling, when they would meet the foot.
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
            projectsScroll.bottomAnchor.constraint(lessThanOrEqualTo: foot.topAnchor, constant: -UILooks.pt(R.gap)),
            foot.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -UILooks.pt(R.padding.bottom)),
            foot.centerXAnchor.constraint(equalTo: centerXAnchor),
            separator.widthAnchor.constraint(equalToConstant: UILooks.pt(R.Separator.width)),
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
                ended ? self.dragEnded(tile) : self.dragMoved(tile, event)
            }
            return tile
        }
        // After the requests' box, which leads the strip (plan 38 G).
        for (index, tile) in tiles.enumerated() { top.insertArrangedSubview(tile, at: index + 1) }
        // The pinned ones first, then a line, then the open ones not pinned (the Dock's two parts).
        if let first = tiles.firstIndex(where: { !$0.project.pinned }), first > 0 {
            top.insertArrangedSubview(groupLine, at: first + 1)
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

    /// For tests: the tiles' folders, the chosen one, the foot's commands, the requests' box.
    var tileIDs: [String] { tiles.map(\.project.id) }
    var chosenID: String? { tiles.first(where: \.chosen)?.project.id }
    var footCommands: [String] { footButtons.map(\.command) }
    func pressFoot(_ index: Int) { footButtons[index].onPress?() }
    var askingShown: Bool { !asking.isHidden }
}

/// The projects' clip: laid from the top, so the first project sits under the padding.
private final class RailClip: NSClipView {
    override var isFlipped: Bool { true }
}
