import AppKit
import Strings
import UILooks

/// A session's retrievals (upstream's print 15; MemorySession.dc.html, "Recuperações", no board of
/// its own): the session screen's frame, "‹ Linha do tempo da sessão", "Histórico de recuperações",
/// and a box per search the agent ran (scope, when, the query in mono, results, limit, duration and
/// the hits, each opening its page); with none, one line.
@MainActor
final class PanelRetrievalsView: PanelScreen {
    let ref: PanelProjectRef
    let session: String
    let retrievals: PanelRetrievals
    private let now: Date

    init(_ ref: PanelProjectRef, session: String, retrievals: PanelRetrievals, now: Date = Date(), go: @escaping (PanelPlace) -> Void) {
        (self.ref, self.session, self.retrievals, self.now) = (ref, session, retrievals, now)
        super.init(go: go)
        setAccessibilityLabel(T("Retrieval history", "Histórico de recuperações"))
        let back = PanelLink("‹ " + T("Session timeline", "Linha do tempo da sessão"), size: MP.Breadcrumb.fontSize) {
            go(.session(ref, session, offset: 0))
        }
        var views: [NSView] = [trail(PanelPlace.retrievals(ref, session, offset: retrievals.offset).crumbs, links: [back]),
                               heading(T("Retrieval history", "Histórico de recuperações"))]
        if retrievals.records.isEmpty {
            views.append(PanelScreen.note(T("No retrieval recorded for this session.", "Nenhuma recuperação registrada para esta sessão.")))
        } else {
            let pager = PanelPager(offset: retrievals.offset, limit: retrievals.limit, total: retrievals.total)
            views.append(PanelPagerBar(pager) { offset in go(.retrievals(ref, session, offset: offset)) })
            views += retrievals.records.map(box)
        }
        fill(views)
        column.setCustomSpacing(UILooks.pt(MP.Head.titleGap), after: views[0])
    }

    private func box(_ r: PanelRetrieval) -> NSView {
        let meta = DesignTokens.FontSize.meta
        let head = PanelText.row([PanelChip.make(r.scope, .neutral),
                                  PanelText.line(r.created.map { PanelWords.ago($0, now: now) } ?? "", size: meta, color: MP.Head.meta),
                                  PanelText.spring()], gap: MP.Chip.gap)
        let query = NSTextField(wrappingLabelWithString: r.query)
        query.font = UILooks.monospaced(MP.Mono.fontSize)
        query.textColor = DesignTokens.Color.textPrimary
        query.isSelectable = true
        let millis = PanelWords.number(r.durationMicros / 1000)
        let facts = PanelText.line(T("\(r.resultCount) results · limit \(r.limit) · \(millis) ms", "\(r.resultCount) resultados · limite \(r.limit) · \(millis) ms"),
                                   size: meta, color: MP.Head.meta)
        var parts: [NSView] = [head, query, facts]
        if let notice = r.notice { parts.append(PanelScreen.note(notice, color: MP.Notice.title)) }
        for hit in r.hits {
            parts.append(PanelLink("\(hit.position). \(hit.path) →", size: meta) { [weak self] in
                guard let self else { return }
                self.go(.page(self.ref, hit.path))
            })
        }
        let column = PanelText.column(parts, gap: MP.Event.gap)
        query.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        head.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        let box = FrameBox()
        box.box(bg: MP.Event.bg, border: MP.Event.border, radius: MP.Event.radius)
        box.hold(column, padding: MP.Event.padding)
        return box
    }
}
