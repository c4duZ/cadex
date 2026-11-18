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
    private let top = NSStackView()
    private let foot = NSStackView()
    private var shown: (projects: [RailProject], chosen: String?)?
    private(set) var tiles: [RailTile] = []
    private let add: RailButton
    private let footButtons: [(RailFoot, RailButton)]

    public init(run: @escaping (String) -> Void) {
        self.run = run
        add = RailButton(command: "project.create", icon: .plus, tip: T("New Project…", "Novo projeto…"))
        footButtons = [
            (.projects, RailButton(command: "project.show-all", icon: .squaresFour, tip: T("Projects", "Projetos"))),
            (.automations, RailButton(command: "orchestration.show-automations", icon: .clock, tip: T("Automations", "Automações"))),
        ]
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = R.bg.cgColor
        add.onPress = { [weak self] in self?.run("project.create") }
        for (_, button) in footButtons {
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
        for (_, button) in footButtons { foot.addArrangedSubview(button) }
        top.addArrangedSubview(add)
        for view in [top, foot, border] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let hairline = DesignTokens.Stroke.hairline
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(R.padding.top)),
            top.centerXAnchor.constraint(equalTo: centerXAnchor),
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
        tiles = projects.map { project in
            let tile = RailTile(project: project, chosen: project.id == chosen)
            tile.onPress = { [weak self] in self?.onPick?(project.id) }
            tile.onMenu = { [weak self, weak tile] event in
                guard let self, let tile, let entries = self.menuFor?(project.id), !entries.isEmpty else { return }
                PopupMenu.show(entries, at: tile.convert(event.locationInWindow, from: nil), in: tile)
            }
            tile.onDropImage = { [weak self] url in self?.onDropImage?(project.id, url) }
            return tile
        }
        for (index, tile) in tiles.enumerated() { top.insertArrangedSubview(tile, at: index) }
    }

    private func lightFoot() {
        for (page, button) in footButtons { button.lit = page == footLit }
    }

    /// For tests: the tiles' folders, the chosen one, the foot's commands and what is lit.
    var tileIDs: [String] { tiles.map(\.project.id) }
    var chosenID: String? { tiles.first(where: \.chosen)?.project.id }
    var footCommands: [String] { footButtons.map(\.1.command) }
    var litCommands: [String] { footButtons.filter(\.1.lit).map(\.1.command) }
}
