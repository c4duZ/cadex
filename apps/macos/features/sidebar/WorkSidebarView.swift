import AppKit
import Icons
import Menus
import Strings
import UILooks

/// The sidebar (docs/adr/0039-sidebar-with-work-and-files.md; plan 38; the reference
/// docs/design/sidebar/6-estrutura-ideal.html): the needs-you queue on top (the app gives it), the
/// "Trabalho | Arquivos" switch, then the Work list (projects, their main and tasks) or the Files
/// view (the app's explorer and Changes, `setFiles`), and the foot (Board, Automations, Machines).
/// Every click comes back by a callback or runs a command by id (ADR 0005).
@MainActor
public final class WorkSidebarView: NSView {
    typealias W = DesignTokens.WorkSidebar
    public var onPickProject: ((String) -> Void)?
    public var onPickPlace: ((String) -> Void)?
    public var onToggle: ((String) -> Void)?
    public var menuFor: ((String) -> [MenuEntry])?
    /// A right click on a task's line: its menu's entries (each runs a command).
    /// A project line's page icon (shown under the pointer): the app opens that project's page.
    public var onOpenProjectPage: ((String) -> Void)?
    public var menuForPlace: ((String) -> [MenuEntry])?
    /// "N changes · see" clicked, at the end of Files: the app shows Changes there.
    public var onShowChanges: (() -> Void)?
    /// A project dragged to a new place: its folder and the projects' folders in the new order.
    public var onMove: ((String, [String]) -> Void)?
    /// An image file dropped on a project's line: its folder and the file (it becomes the picture).
    public var onDropImage: ((String, URL) -> Void)?
    /// Nothing open: a recent clicked, its folder (the app opens the project).
    public var onPickRecent: ((String) -> Void)?
    /// The switch was clicked: the app shows that view (and runs what goes with it).
    public var onMode: ((WorkSidebarMode) -> Void)?
    /// Machines at the foot: only with some SSH host or tailnet machine.
    public var remoteShown = false { didSet { machines.isHidden = !remoteShown } }
    public private(set) var mode: WorkSidebarMode = .work

    let run: (String) -> Void
    /// The edge of the Work list when a project waiting on you is scrolled out of sight.
    let edge = WorkEdge()
    let switchRow = WorkSwitch()
    let content = NSView()
    let list = NSStackView()
    let scroll = NSScrollView()
    var files: NSView?
    /// Files' parts: the head in words, the host (the app's Files and Changes), the changes line.
    private let filesStack = NSStackView()
    private let filesHead = WorkFilesHead()
    private let changesLine = WorkChangesLine()
    private let foot = NSStackView()
    private var machines = NSView()
    /// The Memória page's parts (plan 40 C, `WorkSidebarMemory.swift`): "‹ Trabalho" in the
    /// switch's place, the sections the app gives, the foot's Memória row.
    let backRow = WorkBackRow()
    public internal(set) var memoryHost: NSView?
    var memoryFoot: WorkFootRow?
    var shown: (projects: [WorkProject], place: String?)?
    /// Nothing open: the recents drawn instead of the projects (`WorkRecents.swift`).
    var recentsShown: [WorkRecent]?

    public init(run: @escaping (String) -> Void) {
        self.run = run
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = W.bg.cgColor
        edge.isHidden = true
        edge.onPress = { [weak self] in self?.scrollToWaiting() }
        content.addSubview(edge)
        edge.translatesAutoresizingMaskIntoConstraints = false
        scroll.contentView.postsBoundsChangedNotifications = true
        clipWatch = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateEdge() }
        }
        switchRow.onPick = { [weak self] mode in self?.onMode?(mode) }
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        let clip = WorkClip()
        clip.drawsBackground = false
        scroll.contentView = clip
        scroll.documentView = list
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        list.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        buildFoot()
        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = W.borderRight.cgColor
        backRow.onPress = { [weak self] in self?.run("sidebar.show-work") }
        let column = NSStackView(views: [switchRow, backRow, content, foot])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 0
        column.setCustomSpacing(UILooks.pt(W.Switch.marginBottom), after: switchRow)
        column.setCustomSpacing(UILooks.pt(DesignTokens.MemoryPanel.Nav.Back.marginBottom), after: backRow)
        for view in [column, border] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let pad = W.padding
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(pad.top)),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(pad.left)),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(pad.right)),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -UILooks.pt(pad.bottom)),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            list.topAnchor.constraint(equalTo: clip.topAnchor),
            list.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            list.widthAnchor.constraint(equalTo: clip.widthAnchor),
            edge.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: UILooks.pt(W.Edge.inset)),
            edge.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -UILooks.pt(W.Edge.inset)),
            edge.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -UILooks.pt(W.Edge.inset)),
            border.topAnchor.constraint(equalTo: topAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.widthAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline),
        ])
        content.setContentHuggingPriority(.init(1), for: .vertical)
        // Each part as wide as the sidebar: a stack's .width alignment left them at their own width,
        // the switch small at the right (seen in the app, 2026-11-19).
        for view in [switchRow, backRow, content, foot] as [NSView] {
            view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }
        setMode(.work)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("WorkSidebarView is created in code") }

    override public var mouseDownCanMoveWindow: Bool { false }

    /// The projects and the place you are in (a folder: main's or a task's); redrawn only when they change.
    public func show(_ projects: [WorkProject], place: String?) {
        if recentsShown == nil, let shown, shown.projects == projects, shown.place == place { return }
        leaveRecents()
        shown = (projects, place)
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let label = NSTextField(labelWithString: T("PROJECTS", "PROJETOS"))
        label.font = UILooks.font(W.Section.fontSize, weight: W.Section.weight)
        label.textColor = W.Section.color
        let labelBox = NSStackView(views: [label])
        labelBox.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(W.Section.padding.left), bottom: 0, right: 0)
        add(labelBox)
        // The board's 6 pt under PROJECTS: as the box's inset it never reached the list, and the label
        // sat 5 pt closer to the first project than the board (measured 2026-11-20, the owner).
        list.setCustomSpacing(UILooks.pt(W.Section.padding.bottom), after: labelBox)
        for project in projects { addProject(project, place: place) }
        // As the reference: the arrow's room, a + where the avatar goes, the quiet color; it began under
        // the arrows, out of line with the projects (the owner, 2026-11-20).
        let new = WorkRow(title: T("New Project…", "Novo projeto…"), caret: nil, caretSlot: true, avatar: WorkIconSlot(.plus), bold: false,
                          dim: true, fontSize: W.Row.fontSize, meta: .none, selected: false)
        new.onPress = { [weak self] in self?.run("project.create") }
        add(new)
        DispatchQueue.main.async { [weak self] in self?.updateEdge() }
    }

    private func addProject(_ project: WorkProject, place: String?) {
        let meta: WorkRow.Meta = project.waiting > 0 && !project.expanded ? .waiting(project.waiting)
            : project.terminals > 0 ? .terminals(project.badge, project.terminals) : .nothing(T("nothing open", "nada aberto"))
        // No places (the home folder's "No project"): nothing to unfold, no arrow; its room stays, the
        // avatar and the name under the others'.
        let row = WorkRow(title: project.name, caret: project.places.isEmpty ? nil : project.expanded, caretSlot: true, avatar: WorkAvatar(project), bold: true,
                          fontSize: W.Row.fontSize, meta: meta, selected: false)
        row.onPress = { [weak self] in self?.onPickProject?(project.id) }
        if onOpenProjectPage != nil {
            row.onOpenPage = { [weak self] in self?.onOpenProjectPage?(project.id) }
        }
        row.onCaret = { [weak self] in self?.onToggle?(project.id) }
        row.rightMenu = { [weak self] in self?.menuFor?(project.id) ?? [] }
        row.onDropImage = { [weak self] url in self?.onDropImage?(project.id, url) }
        row.onDrag = { [weak self, weak row] event, ended in
            guard let self, let row else { return }
            row.alphaValue = ended ? 1 : 0.6
            if ended { self.drop(project.id, at: event) }
        }
        add(row)
        guard project.expanded, !project.places.isEmpty else { return }
        let kids = WorkChildren()
        for item in project.places {
            let line = WorkRow(title: item.name, caret: nil, avatar: nil, bold: false, fontSize: W.Children.fontSize,
                               meta: item.terminals > 0 || item.state != nil ? .terminals(item.state == .idle ? nil : item.state, item.terminals) : .none,
                               selected: item.id == place)
            line.onPress = { [weak self] in self?.onPickPlace?(item.id) }
            // A task's menu (status, hibernate, remove…): it lived on the task's tab item, gone in plan 38.
            if !item.isMain { line.rightMenu = { [weak self] in self?.menuForPlace?(item.id) ?? [] } }
            kids.add(line)
        }
        add(kids)
    }

    /// A project let go: it goes before the first project whose line's middle is under the pointer.
    private func drop(_ folder: String, at event: NSEvent) {
        let rows = list.arrangedSubviews.compactMap { $0 as? WorkRow }.filter { row in shown?.projects.contains { $0.name == row.title } == true }
        let ids = shown?.projects.map(\.id) ?? []
        guard rows.count == ids.count else { return }
        let y = event.locationInWindow.y
        var order = ids.filter { $0 != folder }
        let above = zip(rows, ids).filter { $0.1 != folder && $0.0.convert(NSPoint(x: 0, y: $0.0.bounds.midY), to: nil).y > y }.count
        order.insert(folder, at: min(above, order.count))
        if order != ids { onMove?(folder, order) }
    }

    func add(_ view: NSView) {
        list.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
    }

    /// Work or Files: the list, or the files view the app gave; Memory, the page's sections.
    public func setMode(_ next: WorkSidebarMode) {
        mode = next
        switchRow.select(next)
        showMemoryParts(next == .memory)
        guard recentsShown == nil, next != .memory else { return }
        scroll.isHidden = next != .work
        files?.isHidden = next != .files
        updateEdge()
    }

    /// The Files page's buttons, in the head at the right of the name.
    public func setFilesActions(_ view: NSView) { filesHead.hold(view) }

    /// The list alone, the Files view hidden (nothing open).
    func setFilesHidden(_ hidden: Bool) {
        scroll.isHidden = !hidden
        files?.isHidden = hidden
    }

    /// The Files view (the explorer and Changes, with their header and foot), held for the Files
    /// mode, under the head in words and over the changes line (plan 38 phase D).
    public func setFiles(_ view: NSView) {
        files?.removeFromSuperview()
        filesStack.removeFromSuperview()
        files = filesStack
        filesStack.orientation = .vertical
        filesStack.alignment = .leading
        filesStack.spacing = 0
        filesStack.setViews([filesHead, view, changesLine], in: .top)
        for part in [filesHead, view, changesLine] as [NSView] {
            part.widthAnchor.constraint(equalTo: filesStack.widthAnchor).isActive = true
        }
        view.setContentHuggingPriority(.init(1), for: .vertical)
        filesStack.setCustomSpacing(UILooks.pt(W.Changes.marginTop), after: view)
        changesLine.isHidden = true
        changesLine.onPress = { [weak self] in self?.onShowChanges?() }
        filesStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(filesStack)
        NSLayoutConstraint.activate([
            filesStack.topAnchor.constraint(equalTo: content.topAnchor),
            filesStack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            filesStack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            filesStack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        filesStack.isHidden = mode != .files
    }

    /// Files' head: where it is, in words ("kite-fix", "task of cadex · against main").
    public func setFilesHead(title: String, detail: String) { filesHead.say(title, detail) }

    /// "N changes · see" at the end of the tree; none with no change or while Changes shows.
    public func setChanges(count: Int, showingChanges: Bool) {
        changesLine.say(count)
        changesLine.isHidden = count == 0 || showingChanges
    }

    private var clipWatch: NSObjectProtocol?

    /// A project waiting on you whose line is out of the list's sight: the edge says which, on the
    /// side it is (ADR 0039: no amber may live only inside something hidden).
    func updateEdge() {
        let visible = scroll.contentView.bounds
        let waiting = projectRows().filter { $0.1.waiting > 0 && !$0.1.expanded }
        // The line's frame in the clip's own (flipped) space, where the visible part is.
        let clip = scroll.contentView
        let inClip = { (row: WorkRow) in clip.convert(row.bounds, from: row) }
        guard mode == .work, let out = waiting.first(where: { !visible.intersects(inClip($0.0)) }) else { return edge.isHidden = true }
        let below = inClip(out.0).minY >= visible.maxY
        let count = out.1.waiting
        edge.say((below ? "▼ " : "▲ ") + out.1.name + " · " + (count == 1 ? T("1 request ", "1 pedido ") : T("\(count) requests ", "\(count) pedidos "))
                 + (below ? T("below", "abaixo") : T("above", "acima")))
        edge.isHidden = false
    }

    private func scrollToWaiting() {
        guard let row = projectRows().first(where: { $0.1.waiting > 0 && !$0.1.expanded })?.0 else { return }
        row.scrollToVisible(row.bounds)
        updateEdge()
    }

    /// Each project's line with its project.
    private func projectRows() -> [(WorkRow, WorkProject)] {
        let rows = list.arrangedSubviews.compactMap { $0 as? WorkRow }
        return (shown?.projects ?? []).compactMap { project in rows.first { $0.title == project.name }.map { ($0, project) } }
    }

    private func buildFoot() {
        typealias F = W.Foot
        foot.orientation = .vertical
        foot.alignment = .leading
        foot.spacing = UILooks.pt(F.gap)
        foot.edgeInsets = NSEdgeInsets(top: UILooks.pt(F.padding.top), left: 0, bottom: 0, right: 0)
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = F.borderTop.cgColor
        line.heightAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline).isActive = true
        foot.addArrangedSubview(line)
        line.widthAnchor.constraint(equalTo: foot.widthAnchor).isActive = true
        for (title, icon, command) in [(T("Board", "Quadro"), Icon.kanban, "view.board"),
                                       (T("Automations", "Automações"), Icon.clock, "orchestration.show-automations"),
                                       (T("Machines", "Máquinas"), Icon.globe, "remote.show"),
                                       (T("Memory", "Memória"), Icon.brain, "memory.show-panel")] {
            let row = WorkFootRow(title: title, icon: icon)
            if command == "memory.show-panel" { memoryFoot = row }
            row.onPress = { [weak self] in self?.run(command) }
            foot.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: foot.widthAnchor).isActive = true
            if command == "remote.show" { machines = row; row.isHidden = true }
        }
    }

    /// For tests: the list's lines, the lit one, the mode.
    var lineTitles: [String] { list.arrangedSubviews.flatMap { view -> [String] in
        if let row = view as? WorkRow { return [row.title] }
        if let kids = view as? WorkChildren { return kids.rows.map(\.title) }
        return []
    } }
    var filesShown: Bool { !filesStack.isHidden && filesStack.superview != nil }
    var filesHeadSaid: String { filesHead.said }
    var changesSaid: String { changesLine.isHidden ? "" : changesLine.said }
    var edgeSaid: String { edge.isHidden ? "" : edge.said }
    var litTitle: String? { list.arrangedSubviews.compactMap { $0 as? WorkChildren }.flatMap(\.rows).first(where: \.selected)?.title }
    func press(_ title: String) { (list.arrangedSubviews.compactMap { $0 as? WorkRow } + list.arrangedSubviews.compactMap { $0 as? WorkChildren }.flatMap(\.rows)).first { $0.title == title }?.onPress?() }
}

/// The list's clip, laid from the top.
private final class WorkClip: NSClipView {
    override var isFlipped: Bool { true }
}
