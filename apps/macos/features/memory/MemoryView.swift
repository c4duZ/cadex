import AppKit
import Icons
import Menus
import Strings
import UILooks

/// The Memory tab of the right panel (docs/spec/inspector.md, Memory; plan 22 phase H for what it
/// holds), in one scroll (the owner, 2026-11-18: two scrolls one in the other, the system's words
/// on show and the sessions named by their first sentence made it stiff and hard to read):
/// "Search what this project knows", the proposals waiting, what the agents learned today, the
/// project's rules, the last sessions by the title of their conversation, a way to every page,
/// and the briefing's note. Off, it explains and offers to turn on. It asks the app for its state
/// only when it comes on screen or the owner refreshes.
@MainActor
public final class MemoryView: NSView {
    typealias M = DesignTokens.Inspector.Memory
    /// An account's name by folder, as Agents shows it.
    public var accountName: (String) -> String = { ($0 as NSString).lastPathComponent }
    /// The account of a session by id, when the History knows it.
    public var accountOf: (String) -> String? = { _ in nil }
    /// Where a session ran (its folder's name: the task), when the History knows it.
    public var placeOf: (String) -> String? = { _ in nil }
    /// The title of a session's conversation (the one Claude gave it, or the owner's), when known.
    public var titleOf: (String) -> String? = { _ in nil }
    /// Whether "Open the Session" can resume it (the History has it).
    public var canResume: (String) -> Bool = { _ in false }
    /// The page came on screen (true) or left it (false): the app refreshes.
    public var onShowing: ((Bool) -> Void)?
    /// Runs a command by id: the search, the briefing, the history and Turn On are commands (ADR 0005).
    public var run: ((String) -> Void)?
    public var onOpenPage: ((MemoryPage) -> Void)?
    public var onOpenSession: ((String) -> Void)?
    public var onReveal: ((MemoryPage) -> Void)?
    public var onDelete: ((MemoryPage) -> Void)?
    public var onApprove: ((MemoryProposal) -> Void)?
    public var onReject: ((MemoryProposal) -> Void)?

    public private(set) var state: MemoryPageState?
    public private(set) var isShowing = false
    /// How many of each list the tab shows; the rest are in ⌘K's lists and the Archive.
    static let shownProposals = 3
    static let shownLearned = 3
    static let shownRules = 5
    static let shownSessions = 5
    private let scroll = NSScrollView()
    private let content = MemoryFlipped()
    private let stack = NSStackView()

    public override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = UILooks.pt(M.gap)
        stack.edgeInsets = NSEdgeInsets(top: UILooks.pt(M.padding.top), left: UILooks.pt(M.padding.left),
                                        bottom: UILooks.pt(M.padding.bottom), right: UILooks.pt(M.padding.right))
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = content
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// On screen: in a window and not hidden. The panel keeps every tab in the window and hides
    /// the others (History's rule, make perf 2026-11-14).
    public override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateShowing() }
    public override func viewDidHide() { super.viewDidHide(); updateShowing() }
    public override func viewDidUnhide() { super.viewDidUnhide(); updateShowing() }

    func updateShowing() {
        let shows = window != nil && !isHiddenOrHasHiddenAncestor
        guard shows != isShowing else { return }
        isShowing = shows
        onShowing?(shows)
    }

    /// The state the app gathered.
    public func show(_ state: MemoryPageState) {
        self.state = state
        render()
    }

    /// The History changed: the sessions' titles, accounts and "Open the Session" again.
    public func reloadOrigins() { render() }

    func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let state else { return add(MemoryParts.line(T("Loading…", "Carregando…"))) }
        guard state.enabled else {
            add(MemoryParts.paragraph(MemoryStatusText.offText))
            return add(MemoryParts.button(T("Turn On", "Ligar")) { [weak self] in self?.run?("memory.enable") })
        }
        add(MemoryParts.search { [weak self] in self?.run?("memory.search") })
        if let problem = state.problem { add(MemoryParts.paragraph(problem)) }
        renderProposals(state.proposals)
        let pages = state.tree?.allPages ?? []
        if pages.isEmpty {
            add(MemoryParts.line(state.wikiDir == nil ? T("Nothing yet: it starts with this project's first agent session.",
                                                          "Nada ainda: começa com a primeira sessão de agente deste projeto.")
                                                      : T("Nothing learned yet.", "Nada aprendido ainda.")))
        }
        renderLearned(pages)
        renderRules(pages)
        renderSessions(pages)
        if !pages.isEmpty {
            add(link(T("All \(pages.count) pages", "Todas as \(pages.count) páginas"), status: status(state)) { [weak self] in self?.run?("memory.search") })
        }
        add(MemoryParts.briefing { [weak self] in self?.run?("memory.show-briefing") })
        add(MemoryParts.configure { [weak self] in self?.run?("memory.configure-project") })
    }

    /// "LEARNED TODAY": what an agent wrote today, newest first, the session logs left out.
    private func renderLearned(_ pages: [MemoryPage]) {
        let today = pages.filter { $0.learnedAt.map(Calendar.current.isDateInToday) == true && !Self.isSession($0) }
            .sorted { ($0.learnedAt ?? .distantPast) > ($1.learnedAt ?? .distantPast) }
        guard !today.isEmpty else { return }
        var rows: [NSView] = today.prefix(Self.shownLearned).map(pageRow)
        if today.count > Self.shownLearned {
            rows.append(link(T("See all \(today.count)", "Ver as \(today.count)")) { [weak self] in self?.run?("memory.search") })
        }
        add(MemoryParts.section(Self.title(T("LEARNED TODAY", "APRENDIDO HOJE"), today.count), rows))
    }

    /// "PROJECT RULES": the pages every agent gets (`_rules/`).
    private func renderRules(_ pages: [MemoryPage]) {
        let rules = pages.filter { $0.relative.hasPrefix("_rules/") }
        guard !rules.isEmpty else { return }
        var rows: [NSView] = rules.prefix(Self.shownRules).map(pageRow)
        if rules.count > Self.shownRules {
            rows.append(link(T("See all \(rules.count)", "Ver as \(rules.count)")) { [weak self] in self?.run?("memory.search") })
        }
        add(MemoryParts.section(Self.title(T("PROJECT RULES", "REGRAS DO PROJETO"), rules.count), rows))
    }

    /// "LAST SESSIONS": by their conversation's title, the account and where they ran.
    private func renderSessions(_ pages: [MemoryPage]) {
        let sessions = pages.filter(Self.isSession).sorted { ($0.time ?? .distantPast) > ($1.time ?? .distantPast) }
        guard !sessions.isEmpty else { return }
        var rows: [NSView] = sessions.prefix(Self.shownSessions).map { page in
            let id = page.sessionID
            let title = id.flatMap(titleOf) ?? page.title
            let meta = [id.flatMap(accountOf), id.flatMap(placeOf)].compactMap { $0 }.joined(separator: " · ")
            return MemoryRow(title: title, meta: meta, age: MemoryAge.text(page.time), glyph: .terminalWindow,
                             tint: DesignTokens.Color.textSecondary,
                             press: { [weak self] in self?.onOpenPage?(page) }, menu: { [weak self] in self?.menu(page) ?? [] })
        }
        rows.append(link(T("All in the Archive", "Todas no Archive")) { [weak self] in self?.run?("agents.show-history") })
        add(MemoryParts.section(T("LAST SESSIONS", "ÚLTIMAS SESSÕES"), rows))
    }

    private func renderProposals(_ proposals: [MemoryProposal]) {
        guard !proposals.isEmpty else { return }
        var cards: [NSView] = proposals.prefix(Self.shownProposals).map { proposal in
            MemoryParts.proposal(proposal, approve: { [weak self] in self?.onApprove?(proposal) },
                                 reject: { [weak self] in self?.onReject?(proposal) })
        }
        if proposals.count > Self.shownProposals {
            cards.append(MemoryParts.line(T("More in ⌘K: Approve Memory Proposal…", "Mais no ⌘K: Aprovar proposta da memória…")))
        }
        add(MemoryParts.section(T("WAITING FOR YOU (\(proposals.count))", "ESPERANDO VOCÊ (\(proposals.count))"), cards))
    }

    /// A page's row: its kind's glyph, the title, the age.
    private func pageRow(_ page: MemoryPage) -> NSView {
        let (glyph, tint) = MemoryKind.glyph(page)
        return MemoryRow(title: page.title, meta: nil, age: MemoryAge.text(page.learnedAt ?? page.time), glyph: glyph, tint: tint,
                         press: { [weak self] in self?.onOpenPage?(page) }, menu: { [weak self] in self?.menu(page) ?? [] })
    }

    /// A "see more" line in the link color; `status`, the engine's state in its tip.
    private func link(_ text: String, status: String? = nil, press: @escaping @MainActor () -> Void) -> NSView {
        let label = MemoryText.label(text + " →", size: M.Card.Meta.fontSize, color: DesignTokens.Color.accentLink)
        let box = MemoryBox(views: [label], press: press)
        box.toolTip = status
        return box
    }

    /// The engine's and the agent's state, in a tip: the tab does not draw it.
    private func status(_ state: MemoryPageState) -> String {
        var lines = [MemoryStatusText.engine(state.overview) + " · " + MemoryStatusText.agent(state.agent)]
        lines += [MemoryStatusText.counts(state.overview), MemoryStatusText.imported(state.overview, accountName: accountName)].compactMap { $0 }
        lines += MemoryStatusText.queue(state.agent).map { T("queued: ", "na fila: ") + $0 }
        lines += MemoryStatusText.recent(state.agent)
        return lines.joined(separator: "\n")
    }

    static func isSession(_ page: MemoryPage) -> Bool { page.relative.hasPrefix("sessions/") }
    static func title(_ title: String, _ count: Int) -> String { "\(title)  \(count)" }

    func menu(_ page: MemoryPage) -> [MenuEntry] {
        let session = page.sessionID.flatMap { canResume($0) ? $0 : nil }
        return [MenuEntry(T("Open", "Abrir"), icon: .fileMd) { [weak self] in self?.onOpenPage?(page) },
                MenuEntry(T("Open the Session", "Abrir a sessão"), icon: .terminalWindow, isEnabled: session != nil) { [weak self] in
                    if let session { self?.onOpenSession?(session) }
                },
                MenuEntry(T("Reveal in Finder", "Mostrar no Finder"), icon: .folderOpen) { [weak self] in self?.onReveal?(page) },
                .separator,
                MenuEntry(T("Delete Page…", "Apagar a página…"), icon: .trash) { [weak self] in self?.onDelete?(page) }]
    }

    private func add(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -UILooks.pt(M.padding.left + M.padding.right)).isActive = true
    }
}

/// The scroll's content, top down.
final class MemoryFlipped: NSView {
    override var isFlipped: Bool { true }
}
