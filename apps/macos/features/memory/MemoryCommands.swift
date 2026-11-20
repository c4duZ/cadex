import AppKit
import CommandPalette
import Icons
import Strings
import Tabs
import UILooks

/// What the app does for the Memory page's commands: the agent's CLI, the
/// sidebar and the tabs are the app's.
public struct MemoryPageActions {
    public var show: @MainActor () -> Void
    public var showBriefing: @MainActor () -> Void
    public var reindex: @MainActor () -> Void
    /// The wiki's git history in a tab (plan 22: "histórico pelo git-history").
    public var showHistory: @MainActor () -> Void = {}
    public var refresh: @MainActor () -> Void
    public var turnOn: @MainActor () -> Void
    /// The pending proposals of the window's project, fetched for ⌘K.
    public var proposals: @MainActor (@escaping @MainActor ([MemoryProposal]) -> Void) -> Void
    public var approve: @MainActor (MemoryProposal) -> Void
    public var reject: @MainActor (MemoryProposal) -> Void
    /// A decision by the proposal's id (memory.approve and memory.reject with `id=`, the Memória
    /// panel's buttons; plan 40 G): approve, or reject with the reason given ("" none).
    public var decide: @MainActor (String, Bool, String) -> Void = { _, _, _ in }
    /// The wiki's pages as the Memory tab last read them, and opening one (memory.search).
    public var pages: @MainActor () -> [MemoryPage] = { [] }
    public var openPage: @MainActor (MemoryPage) -> Void = { _ in }

    public init(show: @escaping @MainActor () -> Void, showBriefing: @escaping @MainActor () -> Void, reindex: @escaping @MainActor () -> Void,
                refresh: @escaping @MainActor () -> Void, turnOn: @escaping @MainActor () -> Void,
                proposals: @escaping @MainActor (@escaping @MainActor ([MemoryProposal]) -> Void) -> Void,
                approve: @escaping @MainActor (MemoryProposal) -> Void, reject: @escaping @MainActor (MemoryProposal) -> Void) {
        self.show = show
        self.showBriefing = showBriefing
        self.reindex = reindex
        self.refresh = refresh
        self.turnOn = turnOn
        self.proposals = proposals
        self.approve = approve
        self.reject = reject
    }
}

/// The Memory page's commands (ADR 0005). Approve and Reject open, from
/// ⌘K, the list of pending proposals to pick, as History's commands do.
public enum MemoryPageCommands {
    @MainActor
    public static func commands(palette: CommandPaletteController, actions: MemoryPageActions) -> [Command] {
        func pick(_ placeholder: String, _ act: @escaping @MainActor (MemoryProposal) -> Void) -> Command.Action {
            .run { palette.open(MemoryProposalSource(placeholder: placeholder, load: actions.proposals, choose: act)) }
        }
        return [
            Command(id: "memory.show", title: T("Show Project Memory", "Mostrar a memória do projeto"),
                    keywords: ["memory", "wiki", "sidebar", "memória", "painel"], category: .view, action: .run(actions.show)),
            Command(id: "memory.show-briefing", title: T("What the Next Agent Will Get", "O que o próximo agente vai receber"),
                    keywords: ["memory", "briefing", "context", "next session", "next agent", "memória", "contexto", "próxima sessão", "próximo agente"], category: .view,
                    action: .run(actions.showBriefing)),
            Command(id: "memory.reindex", title: T("Reindex Project Memory", "Reindexar a memória do projeto"),
                    keywords: ["memory", "reindex", "wiki", "commit", "memória", "reindexar"], category: .view, action: .run(actions.reindex)),
            Command(id: "memory.show-history", title: T("Show Memory History", "Mostrar o histórico da memória"),
                    keywords: ["memory", "history", "git", "commits", "wiki", "memória", "histórico"], category: .view,
                    action: .run(actions.showHistory)),
            Command(id: "memory.refresh", title: T("Refresh Memory Page", "Atualizar a página da memória"),
                    keywords: ["memory", "refresh", "reload", "memória", "atualizar"], category: .view, action: .run(actions.refresh)),
            Command(id: "memory.enable", title: T("Turn On Project Memory (All Projects)", "Ligar a memória dos projetos (todos)"),
                    keywords: ["memory", "enable", "turn on", "memória", "ligar"], category: .view, action: .run(actions.turnOn)),
            Command(id: "memory.search", title: T("Search Project Memory…", "Buscar na memória do projeto…"),
                    keywords: ["memory", "search", "wiki", "find", "memória", "buscar"], category: .view,
                    action: .run { palette.open(MemoryPageSource(pages: actions.pages(), open: actions.openPage)) }),
            Command(id: "memory.approve", title: T("Approve Memory Proposal…", "Aprovar proposta da memória…"),
                    keywords: ["memory", "proposal", "approve", "agent", "memória", "proposta", "aprovar"], category: .view,
                    action: pick(T("The proposal to approve", "A proposta a aprovar"), actions.approve))
                .accepting("id=<proposal id>") { request in
                    guard let id = request["id"], !id.isEmpty else { return .failed("id is a pending proposal's id") }
                    actions.decide(id, true, "")
                    return .ok("approving \(id)")
                },
            Command(id: "memory.reject", title: T("Reject Memory Proposal…", "Rejeitar proposta da memória…"),
                    keywords: ["memory", "proposal", "reject", "agent", "memória", "proposta", "rejeitar"], category: .view,
                    action: pick(T("The proposal to reject", "A proposta a rejeitar"), actions.reject))
                .accepting("id=<proposal id> [reason=<why>]") { request in
                    guard let id = request["id"], !id.isEmpty else { return .failed("id is a pending proposal's id") }
                    actions.decide(id, false, request["reason"] ?? "")
                    return .ok("rejecting \(id)")
                },
        ]
    }
}

/// ⌘K's list of pending proposals: fetched once when it opens, then
/// filtered by the words typed.
@MainActor
final class MemoryProposalSource: PaletteSource {
    let placeholder: String
    var emptyText: String { T("No proposal waiting", "Nenhuma proposta esperando") }
    var icon: Icon { .checkCircle }
    private let load: @MainActor (@escaping @MainActor ([MemoryProposal]) -> Void) -> Void
    private let pick: @MainActor (MemoryProposal) -> Void
    private var proposals: [MemoryProposal]?
    private var loading = false
    private var lastQuery = ""
    private var lastShow: (@MainActor ([PaletteItem], String?) -> Void)?

    init(placeholder: String, load: @escaping @MainActor (@escaping @MainActor ([MemoryProposal]) -> Void) -> Void,
         choose: @escaping @MainActor (MemoryProposal) -> Void) {
        self.placeholder = placeholder
        self.load = load
        self.pick = choose
    }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        lastQuery = query
        lastShow = show
        guard let proposals else {
            show([], T("loading", "carregando"))
            if !loading {
                loading = true
                load { [weak self] found in
                    guard let self else { return }
                    self.proposals = found
                    if let show = self.lastShow { self.search(self.lastQuery, show: show) }
                }
            }
            return
        }
        show(Self.matching(proposals, query).map { PaletteItem(id: $0.id, title: $0.title, detail: Self.detail($0), icon: .checkCircle) }, nil)
    }

    func choose(_ item: PaletteItem) {
        if let proposal = proposals?.first(where: { $0.id == item.id }) { pick(proposal) }
    }

    func stop() { lastShow = nil }

    /// Every word in the title, kind, path or summary.
    static func matching(_ proposals: [MemoryProposal], _ query: String) -> [MemoryProposal] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        return proposals.filter { p in
            let text = [p.title, p.kind, p.path, p.summary].joined(separator: " ").lowercased()
            return words.allSatisfy(text.contains)
        }
    }

    static func detail(_ proposal: MemoryProposal) -> String {
        [proposal.kind, proposal.summary.isEmpty ? proposal.path : proposal.summary].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// "What the Next Agent Will Get" (memory.show-briefing): the briefing text as
/// the next session in the project receives it, read-only, in a tab. Said so on top (plan 35 H):
/// it is the preview of the next start, not what a session got (that is in the session's detail,
/// the project page's Sessions).
@MainActor
public final class MemoryBriefingDocument: TabDocument {
    public let view: NSView
    public let identity: String
    public var title: String { Self.heading }
    public static var heading: String { T("The Next Agent Will Get", "O próximo agente vai receber") }
    public static var note: String { T("What a new agent session in this project starts with now. What a past session received is in its summary, in the project's Sessions.",
                               "O que uma sessão de agente nova neste projeto recebe agora. O que uma sessão já recebeu fica no resumo dela, nas Sessões do projeto.") }
    public var hasUnsavedChanges: Bool { false }
    /// The center whole (plan 31 E): something to read, not a pane beside a terminal.
    public var isPage: Bool { true }
    public var onChange: (() -> Void)?
    private let text: NSTextView

    public static func identity(for root: String) -> String { "memory-briefing:" + root }

    public init(root: String, briefing: String) {
        identity = Self.identity(for: root)
        let scroll = NSTextView.scrollableTextView()
        text = scroll.documentView as! NSTextView
        text.isEditable = false
        text.isSelectable = true
        text.font = UILooks.monospaced(12)
        text.textContainerInset = NSSize(width: 12, height: 10)
        view = scroll
        show(briefing)
    }

    /// The briefing again (the command run with the tab open), under what it is.
    public func show(_ briefing: String) {
        let body = briefing.isEmpty
            ? T("The briefing is empty: the memory has nothing for this project yet.", "O briefing está vazio: a memória ainda não tem nada deste projeto.")
            : briefing
        text.string = Self.heading.uppercased() + "\n" + Self.note + "\n\n" + body
    }

    /// The theme's colors (the app passes the editor's, so it reads like a file).
    public func paint(text color: NSColor, background: NSColor) {
        text.textColor = color
        text.backgroundColor = background
        text.insertionPointColor = color
    }

    public func focus() { view.window?.makeFirstResponder(text) }
    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }
    public func close() {}
}
