import AppKit
import Strings
import UILooks

/// A page as the search and the "why" name it: its project and path.
public struct PanelHitKey: Hashable, Sendable {
    public var project: PanelProjectRef
    public var path: String
    public init(project: PanelProjectRef, path: String) {
        self.project = project
        self.path = path
    }
}

/// What a recomputed search says about one page (upstream's knowledge.rs `recall_note` and trace):
/// its trace in a project search, its position across projects, or that it fell out.
public enum PanelWhy: Equatable, Sendable {
    case traced(PanelHitTrace)
    case position(Int)
    case outside

    /// The page `key` in a search answered with `explain=1`.
    public static func find(_ key: PanelHitKey, in result: PanelSearchResult) -> PanelWhy {
        guard let index = result.hits.firstIndex(where: { $0.project == key.project && $0.path == key.path }) else { return .outside }
        if let trace = result.hits[index].trace { return .traced(trace) }
        return .position(index + 1)
    }

    public var note: String {
        switch self {
        case .traced: T("Recomputed now with the current index; not a snapshot of the original search.",
                        "Recalculada agora com o índice atual; não é um retrato da busca original.")
        case .position(let n): T("Recomputed now: text search across projects, position \(n); no fusion to explain.",
                                 "Recalculada agora: busca de texto entre projetos, posição \(n); sem fusão para explicar.")
        case .outside: T("Recomputed now: the page is outside the current results. It may have changed or expired.",
                         "Recalculada agora: a página está fora dos resultados atuais. Pode ter mudado ou expirado.")
        }
    }
}

/// The last line of "Evidências e validade" (MemoryPage.dc.html; plan 40 D left it for E): opened
/// from a search, "Aberta pela pesquisa “engine”" and "Recalcular", which runs that search again
/// with the trace (upstream recomputes on request too) and shows how the page ranked; opened
/// directly, the ⓘ says there is no search to explain.
@MainActor
final class PanelWhyRow: FrameBox {
    typealias Read = (String, @escaping @MainActor (Data?) -> Void) -> Void
    let key: PanelHitKey
    let recall: PanelSearchQuery?
    private let read: Read?
    private let body = PanelText.column([], gap: MP.Chip.gap)
    private(set) var why: PanelWhy?

    init(_ key: PanelHitKey, recall: PanelSearchQuery?, read: Read?) {
        (self.key, self.recall, self.read) = (key, recall, read)
        super.init(frame: .zero)
        let title = PanelText.line(T("Why was this page retrieved?", "Por que esta página foi recuperada?"), size: DesignTokens.FontSize.panel,
                                   color: DesignTokens.Color.textPrimary)
        var head: [NSView] = [title, PanelText.spring()]
        if let recall, !recall.words.isEmpty, read != nil {
            head.insert(PanelText.line(T("Opened from the search “\(recall.words)”", "Aberta pela pesquisa “\(recall.words)”"), size: DesignTokens.FontSize.meta,
                                       color: MP.Head.meta), at: 1)
            head.append(PanelLink(T("Recompute", "Recalcular"), size: DesignTokens.FontSize.meta) { [weak self] in self?.recompute() })
        } else {
            head.append(PanelHelpButton(T("Opened directly: no search brought it here. Open the page from a search to see how it ranked.",
                                          "Aberta diretamente: nenhuma pesquisa a trouxe. Abra a página por uma pesquisa para ver como ela se classificou.")))
        }
        let column = PanelText.column([PanelText.row(head, gap: MP.Chip.gap), body], gap: MP.Chip.gap)
        for view in column.views { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        hold(column, padding: MP.Box.Row.padding)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelWhyRow is created in code") }

    /// The search again, explained, and this page's place in it.
    func recompute() {
        guard let recall, let read else { return }
        var query = recall
        query.explain = true
        read(query.path) { [weak self] data in
            guard let self else { return }
            guard let result = PanelSearchResult.parse(data) else {
                return self.show([PanelScreen.note(T("The search did not answer.", "A pesquisa não respondeu."))])
            }
            let why = PanelWhy.find(self.key, in: result)
            self.why = why
            var views: [NSView] = [PanelScreen.note(why.note)]
            if case .traced(let trace) = why {
                let hit = PanelHit(project: self.key.project, path: self.key.path, title: "", snippet: PanelMarked(text: ""), trace: trace)
                let line = PanelText.line(trace.line, size: MP.Mono.fontSize, color: DesignTokens.Color.textBody)
                line.font = UILooks.monospaced(MP.Mono.fontSize)
                views = [line] + PanelHitRow(hit, words: "") {}.traceRows() + views
            }
            self.show(views)
        }
    }

    private func show(_ views: [NSView]) {
        body.setViews(views, in: .top)
    }
}
