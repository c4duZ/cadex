import AppKit
import Icons
import Strings
import UILooks

/// The Agents page of the sidebar (docs/spec/agents.md, Sessions): the live
/// sessions of every account, grouped by project, each with its sign, name,
/// time in that status and "branch · account"; a click opens its
/// subagents, a double click goes to its terminal. It reads only while it
/// shows: hidden or out of a window it lets go of the controller.
@MainActor
public final class AgentsView: NSView {
    /// Whether a session runs in one of Cadex's terminals (its pid's group
    /// is a terminal's foreground group).
    public var isInCadex: (AgentSession) -> Bool = { _ in false }
    /// A double click: its terminal, or its folder when outside Cadex.
    public var onOpen: ((AgentSession) -> Void)?
    /// "Turn On" when agents.sessions is off.
    public var onEnable: (() -> Void)?
    public var colors = AgentColors() { didSet { render() } }

    private let controller: AgentsController
    private let stack = NSStackView()
    private let scroll = NSScrollView()
    private var token: UUID?
    private var clock: Timer?

    public init(controller: AgentsController = .shared) {
        self.controller = controller
        super.init(frame: .zero)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 10, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let document = Flipped()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AgentsView is created in code") }

    // MARK: Reading only while it shows

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWatching()
    }

    public override func viewDidHide() {
        super.viewDidHide()
        updateWatching()
    }

    public override func viewDidUnhide() {
        super.viewDidUnhide()
        updateWatching()
    }

    private func updateWatching() {
        let shows = window != nil && !isHiddenOrHasHiddenAncestor
        if shows, token == nil {
            token = controller.watch { [weak self] in self?.render() }
            // The "3m" ages move on while the page shows.
            let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.render() } }
            timer.tolerance = 5
            RunLoop.main.add(timer, forMode: .common)
            clock = timer
        } else if !shows, let token {
            controller.stop(token)
            self.token = nil
            clock?.invalidate()
            clock = nil
        }
    }

    // MARK: Drawing the list

    func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard controller.isEnabled else {
            return note(T("Agent sessions are off.", "As sessões de agentes estão desligadas."), button: T("Turn On", "Ligar"))
        }
        let groups = AgentsLayout.groups(controller.sessions)
        if groups.isEmpty {
            note(T("No agents running. Start one in a terminal: claude", "Nenhum agente rodando. Abra um num terminal: claude"))
        }
        for group in groups {
            add(header(group))
            for session in group.sessions {
                add(row(for: session, project: group.project))
                if controller.openSession == session.id { addSubagents() }
            }
        }
        if controller.unreadable > 0 {
            note(T("Some sessions could not be read (a newer Claude Code?).", "Algumas sessões não foram lidas (Claude Code mais novo?)."))
        }
    }

    private func add(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -12).isActive = true
    }

    private func header(_ group: AgentsLayout.Group) -> NSView {
        let line = NSStackView(views: [AgentText.icon(.folder, size: 13, color: colors.accent),
                                       AgentText.label(group.project.name, size: 12, weight: .semibold, color: colors.text),
                                       AgentText.label("\(group.sessions.count)", size: 11, color: colors.secondary)])
        line.spacing = 7
        let row = AgentRow(line, inset: 6)
        row.toolTip = group.project.root
        return paddedTop(row)
    }

    private func paddedTop(_ view: NSView) -> NSView {
        let box = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            view.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: box.trailingAnchor),
        ])
        return box
    }

    private func row(for session: AgentSession, project: AgentProject) -> NSView {
        let kind: AgentSign.Kind = switch session.status {
        case .working: .working
        case .waiting: .waiting
        case .other: .unknown
        }
        let name = AgentText.label(session.name, size: 13, color: colors.text)
        let age = AgentText.label(AgentTime.short(since: session.since), size: 11, color: colors.secondary)
        age.setContentCompressionResistancePriority(.required, for: .horizontal)
        let top = NSStackView(views: [name, NSView(), age])
        top.spacing = 6
        let detail = AgentText.label(AgentsLayout.detail(session, project: project, inCadex: isInCadex(session)), size: 11, color: colors.secondary)
        let texts = NSStackView(views: [top, detail])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 1
        top.widthAnchor.constraint(equalTo: texts.widthAnchor).isActive = true
        let line = NSStackView(views: [AgentSign(kind, colors: colors, size: UILooks.pt(11)), texts])
        line.spacing = 8
        line.alignment = .top
        // The texts take the row's width, so the time sits at the right edge
        // whatever the line under the name is.
        texts.trailingAnchor.constraint(equalTo: line.trailingAnchor).isActive = true
        let row = AgentRow(line)
        row.fill = controller.openSession == session.id ? colors.fill : nil
        row.toolTip = "\(session.cwd)\n\(session.account.name) · pid \(session.pid)"
        row.onClick = { [weak self] in self?.controller.toggle(session.id) }
        row.onDoubleClick = { [weak self] in self?.onOpen?(session) }
        return row
    }

    private func addSubagents() {
        let subagents = controller.subagents
        let title = subagents.isEmpty ? T("No subagents", "Nenhum subagente") : T("\(subagents.count) subagents", "\(subagents.count) subagentes")
        add(AgentRow(AgentText.label(title, size: 11, color: colors.secondary), inset: 25))
        for agent in subagents {
            let line = NSStackView(views: [AgentSign(agent.isRunning ? .working : .done, colors: colors, size: UILooks.pt(9)),
                                           AgentText.label(agent.description, size: 12, color: colors.text),
                                           NSView(),
                                           AgentText.label(AgentTime.short(since: agent.lastWrite), size: 11, color: colors.secondary)])
            line.spacing = 7
            let row = AgentRow(line, inset: 25)
            row.toolTip = "\(agent.type): \(agent.description)"
            add(row)
        }
    }

    private func note(_ text: String, button: String? = nil) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = UILooks.font(12)
        label.textColor = colors.secondary
        var views: [NSView] = [label]
        if let button {
            let control = NSButton(title: button, target: self, action: #selector(enable))
            views.append(control)
        }
        let box = NSStackView(views: views)
        box.orientation = .vertical
        box.alignment = .leading
        box.edgeInsets = NSEdgeInsets(top: 12, left: 6, bottom: 4, right: 6)
        add(box)
    }

    @objc private func enable() { onEnable?() }
}

/// A view whose origin is the top left, so the list starts at the top.
private final class Flipped: NSView {
    override var isFlipped: Bool { true }
}
