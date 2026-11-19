import AppKit
import Icons
import Strings
import UILooks

/// The page screen (MemoryPage.dc.html, upstream's page, print 10): the trail to the path, the
/// title, the chips (tier, kind, pinned, expired), "Atualizada · Histórico · Criada", what it
/// replaces and its author; the "Evidências e validade" box; the Markdown; and at the right "Nesta
/// página", CITADA POR and "Cita". A page link opens that page here.
@MainActor
final class PanelPageView: PanelScreen {
    let ref: PanelProjectRef
    let page: PanelPageDetail
    let evidence: PanelEvidence
    private(set) var text: PanelTextView?
    private(set) var evidenceOpen = true
    private let evidenceHost = PanelText.column([], gap: 0)
    private let now: Date

    init(_ ref: PanelProjectRef, page: PanelPageDetail, evidence: PanelEvidence, now: Date = Date(), go: @escaping (PanelPlace) -> Void) {
        (self.ref, self.page, self.evidence, self.now) = (ref, page, evidence, now)
        super.init(go: go)
        setAccessibilityLabel(page.title)
        let rendered = PanelMarkdown.render(page.body)
        let markdown = PanelTextView(rendered.text) { [weak self] path in
            guard let self else { return }
            self.go(.page(ref, path))
        }
        text = markdown
        let title = PanelText.line(page.title, size: MP.Head.Title.fontSize, color: DesignTokens.Color.textPrimary, weight: MP.Head.Title.weight)
        let main = PanelText.column([title, metaLine(), evidenceHost, markdown], gap: MP.Page.gap)
        main.setCustomSpacing(UILooks.pt(MP.Head.titleGap), after: title)
        for view in [evidenceHost, markdown] { view.widthAnchor.constraint(equalTo: main.widthAnchor).isActive = true }
        drawEvidence()
        let side = aside(rendered.headings)
        let row = PanelText.row([main, side], gap: MP.Page.padding.left)
        row.alignment = .top
        side.widthAnchor.constraint(equalToConstant: UILooks.pt(MP.Aside.width)).isActive = true
        main.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -UILooks.pt(MP.Aside.width) - UILooks.pt(MP.Page.padding.left)).isActive = true
        fill([trail(PanelPlace.page(ref, page.path).crumbs), row])
        column.setCustomSpacing(UILooks.pt(MP.Head.titleGap), after: column.arrangedSubviews[0])
    }

    private func metaLine() -> NSView {
        let meta = DesignTokens.FontSize.meta
        var views: [NSView] = [PanelChip.make(page.tier, .green, dot: true)]
        if !page.kind.isEmpty { views.append(PanelChip.make(page.kind, .neutral)) }
        if page.pinned { views.append(PanelChip.make(T("pinned", "fixada"), .neutral)) }
        if evidence.expired { views.append(PanelChip.make(T("expired", "expirada"), .amber, dot: true)) }
        func words(_ text: String) -> NSTextField { PanelText.line(text, size: meta, color: MP.Head.meta) }
        func dot() -> NSTextField { PanelText.line("·", size: meta, color: MP.Breadcrumb.separator) }
        if let updated = page.updated { views.append(words(T("Updated ", "Atualizada ") + PanelWords.ago(updated, now: now))) }
        views += [dot(), PanelLink(T("History", "Histórico"), size: meta) { [weak self] in
            guard let self else { return }
            self.go(.history(self.ref, self.page.path, from: nil, to: nil))
        }]
        if let created = page.created { views += [dot(), words(T("Created ", "Criada ") + PanelWords.ago(created, now: now))] }
        if let supersedes = page.supersedes, supersedes != page.path { views += [dot(), words(T("replaces ", "substitui ") + supersedes)] }
        if let author = evidence.author { views += [dot(), words(T("by ", "por ") + author)] }
        return PanelText.row(views + [PanelText.spring()], gap: MP.Chip.gap)
    }

    // MARK: Evidências e validade

    private func drawEvidence() {
        let caret = NSImageView(image: (evidenceOpen ? Icon.caretDown : Icon.caretRight).image(size: UILooks.pt(MP.Chip.dot + MP.Chip.dot)))
        caret.contentTintColor = MP.Breadcrumb.color
        let head = PanelPress()
        head.hold(PanelText.row([caret, PanelText.line(T("Evidence and validity", "Evidências e validade"), size: DesignTokens.FontSize.body,
                                                       color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.semibold), PanelText.spring()],
                                gap: MP.Chip.gap), padding: MP.Box.Row.padding)
        head.onPress = { [weak self] in
            self?.evidenceOpen.toggle()
            self?.drawEvidence()
        }
        head.setAccessibilityElement(true)
        head.setAccessibilityRole(.disclosureTriangle)
        head.setAccessibilityLabel(T("Evidence and validity", "Evidências e validade"))
        head.setAccessibilityValue(evidenceOpen ? 1 : 0)
        var rows: [NSView] = [head]
        if evidenceOpen {
            rows += evidenceRows()
            rows.append(why())
        }
        let column = PanelText.column([], gap: 0)
        var all: [NSView] = []
        for (index, row) in rows.enumerated() {
            if index > 0 { all.append(PanelScreen.rule()) }
            all.append(row)
        }
        column.setViews(all, in: .top)
        for view in all { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        let box = PanelScreen.box(column, padding: NSEdgeInsets(top: 0, left: MP.Box.padding.left, bottom: 0, right: MP.Box.padding.right))
        evidenceHost.setViews([box], in: .top)
        box.widthAnchor.constraint(equalTo: evidenceHost.widthAnchor).isActive = true
    }

    private func evidenceRows() -> [NSView] {
        let expiry: String = {
            guard let expires = evidence.expires else { return T("No expiry recorded", "Sem expiração registrada") }
            let when = PanelWords.clock(expires)
            return evidence.expired ? T("Expired \(when): out of normal recall until the retention sweep", "Expirada em \(when): fora da recuperação normal até a limpeza")
                : T("Expires \(when)", "Expira em \(when)")
        }()
        var out = [
            fact(T("Version", "Versão"), evidence.version.isEmpty ? page.id : evidence.version, mono: true,
                 help: T("The evidence applies to this indexed version. Recorded citations do not establish truth.",
                         "As evidências se aplicam a esta versão indexada. Citações registradas não comprovam a veracidade.")),
            fact(T("Expiry", "Expiração"), expiry, help: T("Validity is not checked independently.", "A validade não é verificada de forma independente.")),
            fact(T("Readable sources", "Fontes acessíveis"),
                 evidence.sourceCount == 1 ? T("1 recorded citation", "1 citação registrada") : T("\(evidence.sourceCount) recorded citations", "\(evidence.sourceCount) citações registradas"),
                 help: T("No record means the information is unknown, not unfounded. Sources may be unavailable, private or no longer kept.",
                         "A ausência de registros indica informação desconhecida, não falta de fundamento. As fontes podem estar indisponíveis, ser privadas ou não estar mais retidas.")),
        ]
        for source in evidence.sources {
            out.append(fact("", source.kind + (source.created.map { " · " + PanelWords.clock($0) } ?? ""), help: nil))
        }
        out.append(fact(T("Declared contradictions", "Contradições declaradas"),
                        evidence.contradictionCount == 1 ? T("1 live, readable link", "1 conexão ativa e acessível") : T("\(evidence.contradictionCount) live, readable links", "\(evidence.contradictionCount) conexões ativas e acessíveis"),
                        help: T("At most 20 shown. They are declared relations, with no judgement of which is right. None does not prove consistency.",
                                "No máximo 20 exibidas. São relações declaradas, sem julgamento de correção. A ausência não comprova consistência.")))
        for edge in evidence.contradictions {
            let link = PanelLink((edge.outgoing ? "→ " : "← ") + edge.title, size: DesignTokens.FontSize.meta) { [weak self] in
                guard let self else { return }
                self.go(.page(self.ref, edge.path))
            }
            out.append(PanelText.row([spacer(), link, PanelText.spring()], gap: MP.Box.Row.gap))
        }
        return out
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.widthAnchor.constraint(equalToConstant: UILooks.pt(MP.Box.Row.nameWidth)).isActive = true
        return view
    }

    /// A line of the box: the name, the short value and the ⓘ with the rest (screens-memory.md, MemoryPage).
    private func fact(_ name: String, _ value: String, mono: Bool = false, help: String?) -> NSView {
        let label = PanelText.line(name, size: DesignTokens.FontSize.panel, color: MP.Box.Row.name)
        label.widthAnchor.constraint(equalToConstant: UILooks.pt(MP.Box.Row.nameWidth)).isActive = true
        let words = PanelText.line(value, size: DesignTokens.FontSize.panel, color: MP.Box.Row.value)
        if mono { words.font = UILooks.monospaced(MP.Mono.fontSize) }
        words.isSelectable = mono
        var views: [NSView] = [label, words, PanelText.spring()]
        if let help { views.append(PanelHelpButton(help)) }
        let holder = FrameBox()
        holder.hold(PanelText.row(views, gap: MP.Box.Row.gap), padding: MP.Box.Row.padding)
        holder.setAccessibilityElement(true)
        holder.setAccessibilityLabel(name + " " + value)
        return holder
    }

    private func why() -> NSView {
        let line = PanelText.line(T("Why was this page retrieved?", "Por que esta página foi recuperada?"), size: DesignTokens.FontSize.panel,
                                  color: DesignTokens.Color.textPrimary)
        let help = PanelHelpButton(T("Open the page from a search to see how it ranked for that query.",
                                     "Abra a página por uma busca para ver como ela se classificou para aquela consulta."))
        let holder = FrameBox()
        holder.hold(PanelText.row([line, PanelText.spring(), help], gap: MP.Chip.gap), padding: MP.Box.Row.padding)
        return holder
    }

    // MARK: The right column

    private func aside(_ headings: [PanelMarkdown.Heading]) -> NSView {
        var views: [NSView] = []
        if !headings.isEmpty {
            views.append(PanelScreen.label(T("On this page", "Nesta página")))
            views += headings.map { PanelText.line($0.text, size: DesignTokens.FontSize.meta, color: MP.Head.meta) }
        }
        views.append(PanelScreen.label(T("Cited by", "Citada por")))
        if page.backlinks.isEmpty {
            views.append(PanelScreen.note(T("No page points here.", "Nenhuma página aponta para cá.")))
        }
        let shown = page.backlinks.prefix(20)
        views += shown.map { link in pageLink(link) }
        if page.backlinks.count > shown.count {
            views.append(PanelScreen.note(T("and \(page.backlinks.count - shown.count) more", "e mais \(page.backlinks.count - shown.count)")))
        }
        if !page.links.isEmpty {
            views.append(PanelScreen.label(T("Cites", "Cita")))
            views += page.links.map { pageLink($0) }
        }
        let column = PanelText.column(views, gap: MP.Chip.gap)
        for view in views { view.widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor).isActive = true }
        let holder = FrameBox()
        holder.hold(column, padding: NSEdgeInsets(top: MP.Aside.paddingTop, left: 0, bottom: 0, right: 0))
        return holder
    }

    /// A page of another project shows its project first ("site · Deploy") and opens there.
    private func pageLink(_ link: PanelPageLink) -> NSView {
        let other = !link.project.isEmpty && link.project != ref.name
        let target = other ? PanelProjectRef(workspace: ref.workspace, name: link.project) : ref
        return PanelLink((other ? link.project + " · " : "") + link.title, size: DesignTokens.FontSize.meta) { [weak self] in
            self?.go(.page(target, link.path))
        }
    }

    /// For tests.
    func toggleEvidence() { evidenceOpen.toggle(); drawEvidence() }
}
