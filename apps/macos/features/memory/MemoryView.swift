import AppKit
import Menus
import Strings
import UILooks

/// The Memory tab of the right panel (docs/spec/inspector.md, Memory; the Inspector mockup; plan
/// 26 phase C2c; plan 22 phase H for what it holds): "Search what this project knows", what the
/// agents learned today, the proposals waiting for the owner, the wiki with its counts, the
/// engine's state in one line and the briefing's note. Off, it explains and offers to turn on. It
/// asks the app for its state only when it comes on screen or the owner refreshes.
@MainActor
public final class MemoryView: NSView {
    typealias M = DesignTokens.Inspector.Memory
    /// An account's name by folder, as Agents shows it.
    public var accountName: (String) -> String = { ($0 as NSString).lastPathComponent }
    /// The account of a session by id, when the History knows it.
    public var accountOf: (String) -> String? = { _ in nil } { didSet { outline.accountOf = accountOf } }
    /// Where a session ran (its folder's name: the task), when the History knows it.
    public var placeOf: (String) -> String? = { _ in nil }
    /// Whether "Open the Session" can resume it (the History has it).
    public var canResume: (String) -> Bool = { _ in false }
    /// The page came on screen (true) or left it (false): the app refreshes.
    public var onShowing: ((Bool) -> Void)?
    /// Runs a command by id: the search, the briefing and Turn On are commands (ADR 0005).
    public var run: ((String) -> Void)?
    public var onOpenPage: ((MemoryPage) -> Void)?
    public var onOpenSession: ((String) -> Void)?
    public var onReveal: ((MemoryPage) -> Void)?
    public var onDelete: ((MemoryPage) -> Void)?
    public var onApprove: ((MemoryProposal) -> Void)?
    public var onReject: ((MemoryProposal) -> Void)?

    public private(set) var state: MemoryPageState?
    public private(set) var isShowing = false
    /// Proposals and today's pages shown here; the rest are in ⌘K's lists.
    static let shownProposals = 3
    static let shownLearned = 3
    let outline = MemoryWikiOutline()
    private let top = NSStackView()
    private let scroll = NSScrollView()
    private let bottom = NSStackView()

    public override init(frame: NSRect) {
        super.init(frame: frame)
        for stack in [top, bottom] {
            // A short panel clips these instead of breaking a constraint and drawing one over the
            // other (review of 2026-11-17); the wiki between them shrinks first.
            stack.setClippingResistancePriority(.defaultLow, for: .vertical)
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = UILooks.pt(M.gap)
            stack.edgeInsets = NSEdgeInsets(top: UILooks.pt(M.padding.top), left: UILooks.pt(M.padding.left),
                                            bottom: UILooks.pt(M.padding.bottom), right: UILooks.pt(M.padding.right))
        }
        outline.menuFor = { [weak self] page in self?.menu(page) ?? [] }
        outline.onOpen = { [weak self] page in self?.onOpenPage?(page) }
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        for view in [top, scroll, bottom] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: leadingAnchor), top.trailingAnchor.constraint(equalTo: trailingAnchor),
            top.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(M.padding.left)),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(M.padding.right)),
            scroll.topAnchor.constraint(equalTo: top.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottom.topAnchor),
            bottom.leadingAnchor.constraint(equalTo: leadingAnchor), bottom.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: bottomAnchor),
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

    /// The History changed: the pages' accounts and "Open the Session" again.
    public func reloadOrigins() { outline.reloadData() }

    func render() {
        for stack in [top, bottom] { stack.arrangedSubviews.forEach { $0.removeFromSuperview() } }
        guard let state else { return add(MemoryParts.line(T("Loading…", "Carregando…")), to: top) }
        guard state.enabled else {
            outline.show(nil)
            scroll.isHidden = true
            add(MemoryParts.paragraph(MemoryStatusText.offText), to: top)
            return add(MemoryParts.button(T("Turn On", "Ligar")) { [weak self] in self?.run?("memory.enable") }, to: top)
        }
        scroll.isHidden = false
        add(MemoryParts.search { [weak self] in self?.run?("memory.search") }, to: top)
        if let problem = state.problem { add(MemoryParts.paragraph(problem), to: top) }
        renderProposals(state.proposals)
        renderLearned(state.tree?.allPages ?? [])
        // The engine's state is not in the drawing: it stays under the pointer on WIKI.
        var status = [MemoryStatusText.engine(state.overview) + " · " + MemoryStatusText.agent(state.agent)]
        status += [MemoryStatusText.counts(state.overview), MemoryStatusText.imported(state.overview, accountName: accountName)].compactMap { $0 }
        status += MemoryStatusText.queue(state.agent).map { T("queued: ", "na fila: ") + $0 }
        status += MemoryStatusText.recent(state.agent)
        let wiki = MemoryParts.label("WIKI")
        wiki.toolTip = status.joined(separator: "\n")
        add(wiki, to: top)
        if state.tree == nil || state.tree?.count == 0 {
            add(MemoryParts.line(state.wikiDir == nil ? T("No wiki yet: it starts with this project's first agent session.",
                                                          "Nenhuma wiki ainda: começa com a primeira sessão de agente deste projeto.")
                                                      : T("The wiki is empty.", "A wiki está vazia.")), to: top)
        }
        outline.show(state.tree)
        add(MemoryParts.briefing { [weak self] in self?.run?("memory.show-briefing") }, to: bottom)
    }

    /// "LEARNED TODAY": the pages the agents wrote today, newest first.
    private func renderLearned(_ pages: [MemoryPage]) {
        // Only what an agent dated today in the page itself, and not the session logs.
        let today = pages.filter { $0.learnedAt.map(Calendar.current.isDateInToday) == true && !$0.relative.hasPrefix("sessions/") }
            .sorted { ($0.learnedAt ?? .distantPast) > ($1.learnedAt ?? .distantPast) }
        guard !today.isEmpty else { return }
        var cards: [NSView] = today.prefix(Self.shownLearned).map { page in
            MemoryParts.card(page.title, meta: MemoryStatusText.learned(page, place: page.sessionID.flatMap(placeOf))) { [weak self] in
                self?.onOpenPage?(page)
            }
        }
        if today.count > Self.shownLearned {
            cards.append(MemoryParts.line(T("\(today.count - Self.shownLearned) more in Search", "Mais \(today.count - Self.shownLearned) na busca")))
        }
        add(MemoryParts.section(T("LEARNED TODAY", "APRENDIDO HOJE"), cards), to: top)
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
        add(MemoryParts.section(T("WAITING FOR YOU (\(proposals.count))", "ESPERANDO VOCÊ (\(proposals.count))"), cards), to: top)
    }

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

    private func add(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -UILooks.pt(M.padding.left + M.padding.right)).isActive = true
    }
}
