import AppKit
import Menus
import Strings
import UILooks

/// The Memory page of the sidebar (docs/spec/memory.md, "Página Memory";
/// plan 22 phase H): off, it explains and offers to turn on; on, the
/// engine's and the agent's state, the proposals waiting for the owner and
/// the wiki as a tree. It asks the app for its state only when it comes on
/// screen or the owner refreshes: no timer, no watching while hidden.
@MainActor
public final class MemoryView: NSView {
    public var colors = MemoryColors() { didSet { outline.colors = colors; render() } }
    /// An account's name by folder, as Agents shows it.
    public var accountName: (String) -> String = { ($0 as NSString).lastPathComponent }
    /// The account of a session by id, when the History knows it.
    public var accountOf: (String) -> String? = { _ in nil } { didSet { outline.accountOf = accountOf } }
    /// Whether "Open the Session" can resume it (the History has it).
    public var canResume: (String) -> Bool = { _ in false }
    /// The page came on screen (true) or left it (false): the app refreshes.
    public var onShowing: ((Bool) -> Void)?
    public var onTurnOn: (() -> Void)?
    public var onOpenPage: ((MemoryPage) -> Void)?
    public var onOpenSession: ((String) -> Void)?
    public var onReveal: ((MemoryPage) -> Void)?
    public var onDelete: ((MemoryPage) -> Void)?
    public var onApprove: ((MemoryProposal) -> Void)?
    public var onReject: ((MemoryProposal) -> Void)?

    public private(set) var state: MemoryPageState?
    public private(set) var isShowing = false
    /// Proposals shown on the page; the rest are in ⌘K's list.
    static let shownProposals = 3
    let outline = MemoryWikiOutline()
    private let top = NSStackView()
    private let scroll = NSScrollView()
    private let turnOn = NSButton()

    public override init(frame: NSRect) {
        super.init(frame: frame)
        top.orientation = .vertical
        top.alignment = .leading
        top.spacing = 3
        top.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        turnOn.title = T("Turn On", "Ligar")
        turnOn.bezelStyle = .rounded
        turnOn.target = self
        turnOn.action = #selector(turnOnClicked)
        outline.menuFor = { [weak self] page in self?.menu(page) ?? [] }
        outline.onOpen = { [weak self] page in self?.onOpenPage?(page) }
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        for view in [top, scroll] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: leadingAnchor), top.trailingAnchor.constraint(equalTo: trailingAnchor),
            top.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: top.bottomAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// On screen: in a window and not hidden. The sidebar keeps every page
    /// in the window and hides the others (History's rule, make perf 2026-11-14).
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
        for view in top.arrangedSubviews { view.removeFromSuperview() }
        guard let state else { return add(line(T("Loading…", "Carregando…"))) }
        guard state.enabled else {
            outline.show(nil)
            scroll.isHidden = true
            add(MemoryText.label(MemoryStatusText.offText, size: 12, color: colors.secondary, wraps: true))
            return add(turnOn)
        }
        scroll.isHidden = false
        if let problem = state.problem { add(MemoryText.label(problem, size: 11, color: colors.secondary, wraps: true)) }
        add(line(MemoryStatusText.engine(state.overview)))
        if let counts = MemoryStatusText.counts(state.overview) { add(line(counts)) }
        if let imported = MemoryStatusText.imported(state.overview, accountName: accountName) { add(line(imported)) }
        add(line(MemoryStatusText.agent(state.agent)))
        for job in MemoryStatusText.queue(state.agent) { add(line("  " + T("queued: ", "na fila: ") + job)) }
        for run in MemoryStatusText.recent(state.agent) { add(line("  " + run)) }
        renderProposals(state.proposals)
        if state.tree == nil || state.tree?.count == 0 {
            add(line(state.wikiDir == nil ? T("No wiki yet: it starts with this project's first agent session.",
                                              "Nenhuma wiki ainda: começa com a primeira sessão de agente deste projeto.")
                                          : T("The wiki is empty.", "A wiki está vazia.")))
        }
        outline.show(state.tree)
    }

    private func renderProposals(_ proposals: [MemoryProposal]) {
        guard !proposals.isEmpty else { return }
        add(MemoryText.label(T("Proposals waiting for you (\(proposals.count))", "Propostas esperando você (\(proposals.count))"),
                             size: 12, weight: .semibold, color: colors.text))
        for proposal in proposals.prefix(Self.shownProposals) { add(proposalRow(proposal)) }
        if proposals.count > Self.shownProposals {
            add(line(T("More in ⌘K: Approve Memory Proposal…", "Mais no ⌘K: Aprovar proposta da memória…")))
        }
    }

    private func proposalRow(_ proposal: MemoryProposal) -> NSView {
        let title = MemoryText.label([proposal.title, proposal.kind].filter { !$0.isEmpty }.joined(separator: " · "), size: 12, color: colors.text)
        var views: [NSView] = [title]
        if !proposal.summary.isEmpty { views.append(MemoryText.label(proposal.summary, size: 11, color: colors.secondary, wraps: true)) }
        if !proposal.preview.isEmpty { views.append(MemoryText.label(proposal.preview, size: 11, color: colors.secondary)) }
        let approve = ProposalButton(T("Approve", "Aprovar")) { [weak self] in self?.onApprove?(proposal) }
        let reject = ProposalButton(T("Reject", "Rejeitar")) { [weak self] in self?.onReject?(proposal) }
        views.append(NSStackView(views: [approve, reject]))
        let box = NSStackView(views: views)
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 2
        box.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 4, right: 0)
        return box
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

    @objc private func turnOnClicked() { onTurnOn?() }

    private func line(_ text: String) -> NSTextField { MemoryText.label(text, size: 11, color: colors.secondary) }

    private func add(_ view: NSView) {
        top.addArrangedSubview(view)
        view.widthAnchor.constraint(lessThanOrEqualTo: top.widthAnchor, constant: -16).isActive = true
    }
}

/// A small button running a closure.
private final class ProposalButton: NSButton {
    private var run: (() -> Void)?

    convenience init(_ title: String, run: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.run = run
        bezelStyle = .rounded
        controlSize = .small
        target = self
        action = #selector(pressed)
    }

    @objc private func pressed() { run?() }
}
