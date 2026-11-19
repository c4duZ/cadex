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
    /// A request of the queue clicked: its id (the app goes to its terminal).
    public var onPickRequest: ((String) -> Void)?
    /// A project dragged to a new place: its folder and the projects' folders in the new order.
    public var onMove: ((String, [String]) -> Void)?
    /// The switch was clicked: the app shows that view (and runs what goes with it).
    public var onMode: ((WorkSidebarMode) -> Void)?
    /// Machines at the foot: only with some SSH host or tailnet machine.
    public var remoteShown = false { didSet { machines.isHidden = !remoteShown } }
    public private(set) var mode: WorkSidebarMode = .work

    private let run: (String) -> Void
    private let queueSlot = NSStackView()
    private let queue = WorkQueueView()
    /// The edge of the Work list when a project waiting on you is scrolled out of sight.
    private let edge = WorkEdge()
    private let switchRow = WorkSwitch()
    private let content = NSView()
    private let list = NSStackView()
    private let scroll = NSScrollView()
    private var files: NSView?
    private let foot = NSStackView()
    private var machines = NSView()
    private var shown: (projects: [WorkProject], place: String?)?

    public init(run: @escaping (String) -> Void) {
        self.run = run
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = W.bg.cgColor
        queueSlot.orientation = .vertical
        queueSlot.isHidden = true
        queueSlot.addArrangedSubview(queue)
        queue.widthAnchor.constraint(equalTo: queueSlot.widthAnchor).isActive = true
        queue.onPick = { [weak self] id in self?.onPickRequest?(id) }
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
        let column = NSStackView(views: [queueSlot, switchRow, content, foot])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 0
        column.setCustomSpacing(UILooks.pt(W.Switch.marginBottom), after: switchRow)
        column.setCustomSpacing(UILooks.pt(W.Queue.marginBottom), after: queueSlot)
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
        for view in [queueSlot, switchRow, content, foot] as [NSView] {
            view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }
        setMode(.work)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("WorkSidebarView is created in code") }

    override public var mouseDownCanMoveWindow: Bool { false }

    /// The projects and the place you are in (a folder: main's or a task's); redrawn only when they change.
    public func show(_ projects: [WorkProject], place: String?) {
        if let shown, shown.projects == projects, shown.place == place { return }
        shown = (projects, place)
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let label = NSTextField(labelWithString: T("PROJECTS", "PROJETOS"))
        label.font = UILooks.font(W.Section.fontSize, weight: W.Section.weight)
        label.textColor = W.Section.color
        let labelBox = NSStackView(views: [label])
        labelBox.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(W.Section.padding.left), bottom: UILooks.pt(W.Section.padding.bottom), right: 0)
        add(labelBox)
        for project in projects { addProject(project, place: place) }
        let new = WorkRow(title: T("New Project…", "Novo projeto…"), caret: nil, avatar: nil, bold: false,
                          fontSize: W.Row.fontSize, meta: .none, selected: false)
        new.onPress = { [weak self] in self?.run("project.create") }
        add(new)
        DispatchQueue.main.async { [weak self] in self?.updateEdge() }
    }

    private func addProject(_ project: WorkProject, place: String?) {
        let meta: WorkRow.Meta = project.waiting > 0 && !project.expanded ? .waiting(project.waiting)
            : project.terminals > 0 ? .terminals(project.badge, project.terminals) : .nothing(T("nothing open", "nada aberto"))
        let row = WorkRow(title: project.name, caret: project.expanded, avatar: WorkAvatar(project), bold: true,
                          fontSize: W.Row.fontSize, meta: meta, selected: false)
        row.onPress = { [weak self] in self?.onPickProject?(project.id) }
        row.onCaret = { [weak self] in self?.onToggle?(project.id) }
        row.rightMenu = { [weak self] in self?.menuFor?(project.id) ?? [] }
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

    private func add(_ view: NSView) {
        list.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
    }

    /// Work or Files: the list, or the files view the app gave.
    public func setMode(_ next: WorkSidebarMode) {
        mode = next
        switchRow.select(next)
        scroll.isHidden = next != .work
        files?.isHidden = next != .files
        updateEdge()
    }

    /// The Files view (the explorer and Changes, with their header and foot), held for the Files mode.
    public func setFiles(_ view: NSView) {
        files?.removeFromSuperview()
        files = view
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: content.topAnchor),
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        view.isHidden = mode != .files
    }

    /// The needs-you queue on top (plan 38 phase C), in every view; none hides it.
    public func showQueue(_ requests: [WorkRequest], now: Date = Date()) {
        if requests != queue.shown { queue.show(requests, now: now) }
        queueSlot.isHidden = requests.isEmpty
    }

    /// Where the bell's list opens from: the queue while it shows.
    public var queueAnchor: NSView? { queueSlot.isHidden ? nil : queue }

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
                                       (T("Machines", "Máquinas"), Icon.globe, "remote.show")] {
            let row = WorkFootRow(title: title, icon: icon)
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
    var edgeSaid: String { edge.isHidden ? "" : edge.said }
    var litTitle: String? { list.arrangedSubviews.compactMap { $0 as? WorkChildren }.flatMap(\.rows).first(where: \.selected)?.title }
    func press(_ title: String) { (list.arrangedSubviews.compactMap { $0 as? WorkRow } + list.arrangedSubviews.compactMap { $0 as? WorkChildren }.flatMap(\.rows)).first { $0.title == title }?.onPress?() }
}

/// The list's clip, laid from the top.
private final class WorkClip: NSClipView {
    override var isFlipped: Bool { true }
}
