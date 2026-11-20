import AppKit
import Strings
import UILooks

/// Workstreams gerenciados (MemoryWorkstreams.dc.html, upstream's workstreams page, print 03): the
/// title, "Por atenção e atividade recente" and "Página N"; the table (the name with its project,
/// which opens it, and the short id; the state's chip, green active, amber interrupted; the latest
/// run's agent, short id and "Início há 1 dia; encerrado …" or "Não iniciado"; the events and the
/// harnesses; the activity at the right); Anterior and Próxima with more than one page.
@MainActor
final class PanelWorkstreamsView: PanelScreen {
    typealias W = MP.Workstreams.Shares
    let data: PanelWorkstreams
    let table = PanelTable([PanelColumn(title: "Workstream", share: W.workstream), PanelColumn(title: T("Status", "Estado"), share: W.status),
                            PanelColumn(title: T("Latest run", "Execução mais recente"), share: W.run),
                            PanelColumn(title: T("Evidence", "Evidências"), share: W.evidence),
                            PanelColumn(title: T("Activity", "Atividade"), share: nil)])
    private let now: Date

    init(_ data: PanelWorkstreams, now: Date = Date(), go: @escaping (PanelPlace) -> Void) {
        (self.data, self.now) = (data, now)
        super.init(go: go)
        setAccessibilityLabel(T("Managed workstreams", "Workstreams gerenciados"))
        let page = PanelText.line(T("Page \(data.page)", "Página \(data.page)"), size: DesignTokens.FontSize.meta, color: MP.Head.meta)
        let head = heading(T("Managed workstreams", "Workstreams gerenciados"), buttons: [page])
        let note = PanelScreen.note(T("By attention and recent activity", "Por atenção e atividade recente"))
        note.toolTip = T("Operational state across projects, ordered by attention and recent activity.",
                         "Estado operacional entre projetos, ordenado por necessidade de atenção e atividade recente.")
        var views: [NSView] = [head, note]
        if data.rows.isEmpty {
            views.append(PanelScreen.note(T("No managed workstreams on this page.", "Nenhum workstream gerenciado nesta página.")))
        } else {
            table.show(data.rows.map(cells))
            for (row, item) in zip(table.rows, data.rows) {
                row.setAccessibilityLabel("\(item.name), \(PanelGraph.name(item.project)), \(item.statusTitle)")
            }
            views.append(table)
        }
        if data.page > 1 || data.hasNext { views.append(pager()) }
        fill(views)
        column.setCustomSpacing(UILooks.pt(MP.Empty.gap), after: head)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelWorkstreamsView is created in code") }

    private func cells(_ w: PanelWorkstream) -> [NSView] {
        let meta = DesignTokens.FontSize.meta
        let name = PanelText.line(w.name, size: MP.Table.Row.fontSize, color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.semibold)
        let project = PanelLink(PanelGraph.name(w.project), size: meta) { [weak self] in self?.go(.project(w.project, .overview)) }
        let first = PanelText.column([name, PanelText.row([project, mono(PanelWords.shortID(w.id))], gap: MP.Chip.gap)], gap: 2)
        let tone: PanelChip.Tone = w.status == "active" ? .green : w.status == "interrupted" ? .amber : .neutral
        let status = PanelChip.cell(w.statusTitle, tone, dot: tone != .neutral)
        let run: NSView
        if let agent = w.latestAgent {
            var when = T("Started ", "Início ") + (w.started.map { PanelWords.ago($0, now: now) } ?? "—")
            if let ended = w.ended { when += T("; ended ", "; encerrado ") + PanelWords.ago(ended, now: now) }
            run = PanelText.column([PanelText.row([PanelChip.make(agent, .neutral), mono(w.latestRun.map(PanelWords.shortID) ?? ""), PanelText.spring()],
                                                  gap: MP.Chip.gap),
                                    PanelText.line(when, size: meta, color: MP.Head.meta)], gap: 4)
        } else {
            run = PanelText.line(T("Not launched", "Não iniciado"), size: MP.Table.Row.fontSize, color: MP.Head.meta)
        }
        let count = PanelText.line(w.events == 1 ? T("1 event", "1 evento") : T("\(PanelWords.number(w.events)) events", "\(PanelWords.number(w.events)) eventos"),
                                   size: MP.Table.Row.fontSize, color: MP.Table.Row.color)
        var evidence: [NSView] = [count]
        if !w.harnesses.isEmpty { evidence.append(PanelText.row(w.harnesses.map { PanelChip.make($0, .neutral) } + [PanelText.spring()], gap: 4)) }
        let activity = PanelText.line(w.lastActive.map { PanelWords.ago($0, now: now) } ?? "—", size: meta, color: MP.Head.meta)
        activity.alignment = .right
        return [first, status, run, PanelText.column(evidence, gap: 4), activity]
    }

    private func mono(_ text: String) -> NSTextField {
        let label = PanelText.line(text, size: MP.Mono.fontSize, color: MP.Head.meta)
        label.font = UILooks.monospaced(MP.Mono.fontSize)
        return label
    }

    private func pager() -> NSView {
        var views: [NSView] = []
        if data.page > 1 {
            views.append(PanelLink(T("Previous", "Anterior"), size: DesignTokens.FontSize.panel) { [weak self, data] in
                self?.go(.workstreams(page: data.page - 1))
            })
        }
        views.append(PanelText.spring())
        if data.hasNext {
            views.append(PanelLink(T("Next", "Próxima"), size: DesignTokens.FontSize.panel) { [weak self, data] in
                self?.go(.workstreams(page: data.page + 1))
            })
        }
        return PanelText.row(views, gap: MP.Chip.gap)
    }
}
