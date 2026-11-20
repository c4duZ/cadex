import AppKit
import Strings
import UILooks

/// Revisão de aprendizado (MemoryReview.dc.html, upstream's pending page, print 06): "Gravações
/// pendentes"; Projeto and Ordenação (each choice a new place, no Aplicar) and "N exibidas · N
/// pendentes em N projetos"; a proposal per row that opens (PanelProposalRow). A decision goes out as
/// memory.approve or memory.reject; done, its row leaves and the line above the list says it, as
/// upstream's page does without reloading.
@MainActor
final class PanelReviewView: PanelScreen, PanelWriting {
    let review: PanelReview
    private let write: (PanelWrite) -> Void
    private let reload: () -> Void
    private(set) var rows: [PanelProposalRow] = []
    let projectPopup = PanelPopup(prefix: nil, value: "")
    let sortPopup = PanelPopup(prefix: nil, value: "")
    private let status = PanelScreen.note("")
    private let count = PanelText.line("", size: DesignTokens.FontSize.meta, color: MP.Head.meta)
    private var shown: Int

    init(_ review: PanelReview, now: Date = Date(), write: @escaping (PanelWrite) -> Void, reload: @escaping () -> Void, go: @escaping (PanelPlace) -> Void) {
        (self.review, self.write, self.reload, shown) = (review, write, reload, review.proposals.count)
        super.init(go: go)
        setAccessibilityLabel(T("Pending writes", "Gravações pendentes"))
        let head = heading(T("Pending writes", "Gravações pendentes"))
        let note = PanelScreen.note(T("Auto-improvement proposals waiting for a decision", "Propostas de melhoria automática à espera de decisão"))
        note.toolTip = T("Open a proposal to read it, then approve or reject it.", "Abra uma proposta para lê-la e depois aprove ou rejeite.")
        status.isHidden = true
        var views: [NSView] = [head, note, filters(), status]
        if review.proposals.isEmpty {
            views.append(PanelScreen.note(T("No pending proposals.", "Nenhuma proposta pendente.")))
        } else {
            rows = review.proposals.map { p in
                PanelProposalRow(p, now: now, write: write) { [weak self] in self?.go(.page(p.project, p.path)) }
            }
            var list: [NSView] = []
            for row in rows { list.append(row) }
            let stack = PanelText.column(list, gap: MP.Page.gap / 2)
            for view in list { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
            views.append(stack)
        }
        if review.truncated {
            views.append(PanelScreen.note(T("Only the oldest 500 of this selection are listed: pick a project.",
                                            "Só as 500 mais antigas desta seleção aparecem: escolha um projeto.")))
        }
        fill(views)
        column.setCustomSpacing(UILooks.pt(MP.Empty.gap), after: head)
        counted()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelReviewView is created in code") }

    private func filters() -> NSView {
        let projects = review.scopes.map(\.project)
        let chosen = review.query.project.flatMap { p in projects.firstIndex(of: p).map { $0 + 1 } } ?? 0
        let titles = review.projectTitles
        projectPopup.say(titles[min(chosen, titles.count - 1)])
        projectPopup.offer(titles, chosen: chosen) { [weak self] i in
            guard let self else { return }
            self.go(.review(PanelReviewQuery(project: i == 0 ? nil : projects[i - 1], sort: self.review.query.sort)))
        }
        let sorts = PanelReviewQuery.sorts
        let sortIndex = sorts.firstIndex(of: review.query.sort) ?? 0
        sortPopup.say(PanelReviewQuery.sortTitle(sorts[sortIndex]))
        sortPopup.offer(sorts.map(PanelReviewQuery.sortTitle), chosen: sortIndex) { [weak self] i in
            guard let self else { return }
            self.go(.review(PanelReviewQuery(project: self.review.query.project, sort: sorts[i])))
        }
        let label = { (text: String) in
            PanelText.line(text, size: DesignTokens.FontSize.meta, color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.semibold)
        }
        return PanelText.row([label(T("Project", "Projeto")), projectPopup, label(T("Order", "Ordenação")), sortPopup, PanelText.spring(), count],
                             gap: MP.Chip.gap)
    }

    private func counted() {
        var copy = review
        copy.proposals = Array(copy.proposals.prefix(shown))
        count.stringValue = copy.countLine
    }

    func finished(_ done: PanelWrite, _ answer: Result<Data, PanelReadError>) {
        let id: String, approving: Bool
        switch done {
        case .approve(let which): (id, approving) = (which, true)
        case .reject(let which, _): (id, approving) = (which, false)
        default: return
        }
        guard let row = rows.first(where: { $0.proposal.id == id }) else { return }
        let path = row.proposal.path
        status.isHidden = false
        switch answer {
        case .success:
            row.isHidden = true
            shown -= 1
            counted()
            status.textColor = MP.Ok.color
            status.stringValue = (approving ? T("Approved: ", "Aprovado: ") : T("Rejected: ", "Rejeitado: ")) + path + "."
        case .failure(let e):
            row.failed()
            status.textColor = MP.Inbox.error
            status.stringValue = e.words.contains("changed") || e.words.contains("conflict")
                ? T("The page at \(path) changed after the proposal was staged. The proposal is now marked as a conflict.",
                    "A página em \(path) foi alterada após a preparação da proposta. A proposta agora está marcada como conflito.")
                : (approving ? T("Approve", "Aprovar") : T("Reject", "Rejeitar")) + T(" failed for ", " falhou para ") + path + ": " + e.words
        }
    }

    /// For tests.
    var statusSaid: String { status.isHidden ? "" : status.stringValue }
    var countSaid: String { count.stringValue }
}
