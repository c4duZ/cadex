import AppKit
import Strings
import UILooks

/// Pesquisar na memória (plan 40 E, MemorySearch.dc.html; upstream's search screen): the title
/// with the words marked, "em cadex ×" in a project, the bar (project, kind, tier, the words,
/// "Explicar classificação", Pesquisar), the count, the recall trace when explained, and the hits.
/// With no words, the newest pages. Each change is a new place (memory.show-panel with the
/// search), so back and forward walk the searches; a hit opens its page through `open`, which
/// keeps the search for the page's "Por que esta página foi recuperada?".
@MainActor
final class PanelSearchView: PanelScreen {
    let result: PanelSearchResult
    let field = NSTextField()
    private let open: (PanelHit) -> Void
    private(set) var rows: [PanelHitRow] = []
    private let scopePopup = PanelPopup(prefix: nil, value: "")
    private let kindPopup = PanelPopup(prefix: nil, value: "")
    private let tierPopup = PanelPopup(prefix: nil, value: "")
    private let explainBox = NSButton(checkboxWithTitle: T("Explain ranking", "Explicar classificação"), target: nil, action: nil)
    private(set) var chosen: Int? { didSet { for (i, row) in rows.enumerated() { row.chosen = i == chosen } } }

    init(_ result: PanelSearchResult, open: @escaping (PanelHit) -> Void, go: @escaping (PanelPlace) -> Void) {
        self.result = result
        self.open = open
        super.init(go: go)
        var parts: [NSView] = [title(), bar()]
        parts.append(contentsOf: status())
        if result.query.explain, !result.isRecent { parts.append(traceBox()) }
        rows = result.hits.enumerated().map { index, hit in
            PanelHitRow(hit, words: result.query.words) { [weak self] in
                self?.chosen = index
                open(hit)
            }
        }
        var list: [NSView] = []
        for (index, row) in rows.enumerated() {
            if index > 0 { list.append(PanelScreen.rule(MP.Search.Result.divider)) }
            list.append(row)
        }
        let column = PanelText.column(list, gap: 0)
        for view in list { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        if !list.isEmpty { parts.append(column) }
        fill(parts)
        setAccessibilityLabel(T("Search memory", "Pesquisar na memória"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelSearchView is created in code") }

    override var firstFocus: NSView { field }

    private var query: PanelSearchQuery { result.query }

    /// "Pesquisar: memória" (the words marked as in the hits) and, in a project, "em cadex ×".
    private func title() -> NSView {
        let head = PanelText.line(query.words.isEmpty ? T("Search", "Pesquisar") : T("Search:", "Pesquisar:"), size: MP.Head.Title.fontSize,
                                  color: DesignTokens.Color.textPrimary, weight: MP.Head.Title.weight)
        var views: [NSView] = [head]
        if !query.words.isEmpty {
            let words = PanelMarked(text: query.words, marks: [NSRange(location: 0, length: (query.words as NSString).length)])
            views.append(PanelMarkedLabel(words, size: MP.Head.Title.fontSize, color: DesignTokens.Color.textPrimary, weight: MP.Head.Title.weight))
        }
        if let scope = query.scope {
            let leave = PanelLink(T("in ", "em ") + PanelGraph.name(scope) + "  ×", size: DesignTokens.FontSize.meta) { [weak self] in self?.leaveProject() }
            leave.label.textColor = MP.Chip.Neutral.color
            leave.setAccessibilityLabel(T("Search every project", "Pesquisar em todos os projetos"))
            let chip = FrameBox()
            chip.box(bg: MP.Chip.Neutral.bg, border: nil, radius: MP.Chip.radius)
            chip.hold(leave, padding: MP.Chip.padding)
            views.append(chip)
        }
        return PanelText.row(views + [PanelText.spring()], gap: MP.Head.gap)
    }

    private func bar() -> NSView {
        let projects = [T("All projects", "Todos os projetos")] + result.scopes.map(PanelGraph.name)
        let scopeIndex = query.scope.flatMap { s in result.scopes.firstIndex(of: s).map { $0 + 1 } } ?? 0
        scopePopup.say(projects[scopeIndex])
        scopePopup.offer(projects, chosen: scopeIndex) { [weak self] i in self?.submit { $0.scope = i == 0 ? nil : self?.result.scopes[i - 1] } }
        let kinds = [T("Any kind", "Qualquer tipo")] + result.kinds
        let kindIndex = result.kinds.firstIndex { $0.caseInsensitiveCompare(query.kind) == .orderedSame }.map { $0 + 1 } ?? 0
        kindPopup.say(kinds[kindIndex])
        kindPopup.offer(kinds, chosen: kindIndex) { [weak self] i in self?.submit { $0.kind = i == 0 ? "" : self?.result.kinds[i - 1] ?? "" } }
        let tiers = [T("Any tier", "Qualquer camada")] + result.tiers
        let tierIndex = result.tiers.firstIndex(of: query.tier).map { $0 + 1 } ?? 0
        tierPopup.say(tiers[tierIndex])
        tierPopup.offer(tiers, chosen: tierIndex) { [weak self] i in self?.submit { $0.tier = i == 0 ? "" : self?.result.tiers[i - 1] ?? "" } }
        let box = FrameField.field(field)
        field.font = UILooks.font(MP.Field.fontSize)
        field.stringValue = query.words
        field.placeholderAttributedString = NSAttributedString(string: T("Search pages…", "Pesquisar páginas…"), attributes: [
            .font: UILooks.font(MP.Field.fontSize), .foregroundColor: MP.Field.placeholder,
        ])
        field.setAccessibilityLabel(T("Search words", "Termos da pesquisa"))
        field.target = self
        field.action = #selector(searched)
        box.heightAnchor.constraint(equalToConstant: UILooks.rowHeight(MP.Field.height)).isActive = true
        box.setContentHuggingPriority(.init(1), for: .horizontal)
        // The words take what the row leaves (the board), never under a filter field's width.
        box.widthAnchor.constraint(greaterThanOrEqualToConstant: UILooks.pt(MP.Field.width)).isActive = true
        let wide = box.widthAnchor.constraint(equalToConstant: 10_000)
        wide.priority = .init(240)
        wide.isActive = true
        for fixed in [scopePopup, kindPopup, tierPopup, explainBox] as [NSView] { fixed.setContentCompressionResistancePriority(.required, for: .horizontal) }
        explainBox.state = query.explain ? .on : .off
        explainBox.font = UILooks.font(MP.Field.fontSize)
        explainBox.contentTintColor = MP.Head.meta
        explainBox.target = self
        explainBox.action = #selector(explainToggled)
        let button = DesignButton.make(T("Search", "Pesquisar"), .primary) { [weak self] in self?.searched() }
        return PanelText.row([scopePopup, kindPopup, tierPopup, box, explainBox, button], gap: MP.Chip.gap * 2)
    }

    /// The count, or what an empty list means.
    private func status() -> [NSView] {
        if result.isRecent {
            let line = result.hits.isEmpty ? T("Type a search term above.", "Digite um termo acima.")
                : query.scope == nil ? T("Search, or open a recently updated page.", "Pesquise ou abra uma página atualizada há pouco.")
                : T("Search this project, or open one of its recent pages.", "Pesquise neste projeto ou abra uma das páginas recentes dele.")
            return [PanelScreen.note(line)]
        }
        guard result.hits.isEmpty else { return [PanelScreen.note(result.countLine)] }
        var line = T("No results for \(query.words)", "Nenhum resultado para \(query.words)")
        if result.filtered { line += T(" with these filters", " com estes filtros") }
        var views: [NSView] = [PanelText.line(line + ".", size: DesignTokens.FontSize.body, color: MP.Head.meta)]
        if !result.unknownKind.isEmpty {
            views.append(PanelHelpButton(T("“\(result.unknownKind)” is not one of the known kinds; pages may still use it.",
                                           "“\(result.unknownKind)” não é um dos tipos conhecidos; páginas ainda podem usá-lo.")))
        }
        if query.scope != nil {
            views.append(DesignButton.make(T("Search all projects", "Pesquisar em todos os projetos"), .secondary) { [weak self] in self?.leaveProject() })
        }
        return [PanelText.row(views + [PanelText.spring()], gap: MP.Chip.gap * 2)]
    }

    /// "Rastro da recuperação": the ranker and its streams (a project) or the FTS note (all), the times.
    private func traceBox() -> NSView {
        var lines: [NSView] = [PanelScreen.label(T("Recall trace", "Rastro da recuperação"))]
        if query.scope != nil {
            lines.append(mono(T("Hybrid ranker, like memory_query; streams: ", "Ranker híbrido, como o memory_query; streams: ") + result.streams))
            lines.append(mono("Embedder: \(result.embedder) · Reranker: \(result.reranker)"))
        } else {
            lines.append(PanelScreen.note(T("Across projects: text search (FTS) only, as memory_query(global) does; no per-stream fusion.",
                                            "Entre projetos: só busca de texto (FTS), como o memory_query(global); sem fusão por stream.")))
        }
        for timing in result.timings { lines.append(mono(timing.stream + "  " + timing.ms + " ms")) }
        let column = PanelText.column(lines, gap: MP.Chip.gap)
        return PanelScreen.box(column)
    }

    private func mono(_ text: String) -> NSTextField {
        let label = PanelText.line(text, size: MP.Mono.fontSize, color: DesignTokens.Color.textBody)
        label.font = UILooks.monospaced(MP.Mono.fontSize)
        return label
    }

    // MARK: Going

    /// A new search from the bar's state with `change` applied.
    private func submit(_ change: (inout PanelSearchQuery) -> Void) {
        var next = PanelSearchQuery(words: field.stringValue, scope: query.scope, kind: query.kind, tier: query.tier, explain: explainBox.state == .on)
        change(&next)
        go(.search(next))
    }

    @objc private func searched() { submit { _ in } }
    @objc private func explainToggled() { submit { _ in } }

    private func leaveProject() { submit { $0.scope = nil } }

    // MARK: Keys: ↑ and ↓ choose a hit, Enter opens it (the field keeps its own Enter).

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: choose(by: 1)
        case 126: choose(by: -1)
        case 36, 76: if let chosen { open(rows[chosen].hit) } else { super.keyDown(with: event) }
        default: super.keyDown(with: event)
        }
    }

    func choose(by step: Int) {
        guard !rows.isEmpty else { return }
        chosen = max(0, min(rows.count - 1, (chosen ?? -1) + step))
        if let chosen { rows[chosen].scrollToVisible(rows[chosen].bounds) }
    }

    /// For tests.
    func type(_ words: String) { field.stringValue = words; searched() }
    func pickScope(_ index: Int) { scopePopup.pick(index) }
    func pickKind(_ index: Int) { kindPopup.pick(index) }
    func toggleExplain() { explainBox.state = explainBox.state == .on ? .off : .on; explainToggled() }
    var popupsSaid: [String] { [scopePopup.said, kindPopup.said, tierPopup.said] }
}
