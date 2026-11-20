import AppKit
import Strings
import UILooks

/// Documentação (MemoryDocs.dc.html, upstream's docs index, print 08): the guides stay out of the
/// engine (plan 40 B), so this lists upstream's catalog (PanelGuides.swift) and a click opens the
/// guide on GitHub at the pinned commit (memory.open-guide). The highlight "Comece pelo guia de
/// ativação" with the version and "Explorar recursos"; the field filters by title, description and
/// category as one types; the cards in three columns. With `history`, Histórico de alterações: the
/// changelogs.
@MainActor
final class PanelDocsView: PanelScreen, NSSearchFieldDelegate {
    let history: Bool
    private let open: (PanelGuide) -> Void
    let field = NSSearchField()
    private let count = PanelText.line("", size: DesignTokens.FontSize.meta, color: MP.Head.meta)
    private let grid = PanelText.column([], gap: MP.Page.gap)
    private(set) var shown: [PanelGuide] = []

    init(words: String, history: Bool, open: @escaping (PanelGuide) -> Void, go: @escaping (PanelPlace) -> Void) {
        (self.history, self.open) = (history, open)
        super.init(go: go)
        let title = history ? T("Changelog", "Histórico de alterações") : T("Documentation", "Documentação")
        setAccessibilityLabel(title)
        let other = PanelLink(history ? T("Documentation", "Documentação") : T("Changelog", "Histórico de alterações"),
                              size: DesignTokens.FontSize.panel) { [weak self] in self?.go(.docs(words: "", history: !history)) }
        var views: [NSView] = [heading(title, buttons: [other])]
        if !history { views.append(highlight()) }
        field.placeholderString = T("Search a feature, command or setting…", "Buscar recurso, comando ou chave de configuração…")
        field.stringValue = words
        field.delegate = self
        field.setAccessibilityLabel(T("Filter the guides", "Filtrar os guias"))
        let box = FrameField.field(field)
        box.heightAnchor.constraint(equalToConstant: UILooks.rowHeight(MP.Field.height)).isActive = true
        let help = PanelHelpButton(T("The filter reads each guide's title, description and category. The guides open on GitHub, at the version this Cadex runs.",
                                     "O filtro lê o título, a descrição e a categoria de cada guia. Os guias abrem no GitHub, na versão que este Cadex usa."))
        views.append(PanelText.row([box, count, help], gap: MP.Chip.gap))
        box.setContentHuggingPriority(.init(1), for: .horizontal)
        views.append(grid)
        fill(views)
        filter()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelDocsView is created in code") }

    override var firstFocus: NSView { field }

    /// "Comece pelo guia de ativação", the version, and "Explorar recursos" (the features guide).
    private func highlight() -> NSView {
        let features = PanelGuide.all.first { $0.id == "features" }
        let version = MemoryPanelInfo.upstream.split(separator: " ").last.map(String.init) ?? ""
        let title = PanelText.line(T("Start with the activation guide", "Comece pelo guia de ativação"), size: MP.Section.fontSize,
                                   color: DesignTokens.Color.textPrimary, weight: MP.Section.weight)
        let line = PanelScreen.note(T("Prerequisites, setup and checks", "Pré-requisitos, configuração e verificações"))
        let explore = DesignButton.make(T("Explore features", "Explorar recursos"), .primary) { [weak self] in
            if let features { self?.open(features) }
        }
        let text = PanelText.column([PanelText.row([title, PanelChip.make(T("version ", "versão ") + version, .neutral)], gap: MP.Chip.gap), line], gap: 4)
        return PanelScreen.box(PanelText.row([text, PanelText.spring(), explore], gap: MP.Page.gap))
    }

    func controlTextDidChange(_ obj: Notification) { filter() }

    /// The guides whose title, description or category hold every word typed.
    static func matching(_ words: String, history: Bool) -> [PanelGuide] {
        let terms = words.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return PanelGuide.all.filter { $0.isChangelog == history }.filter { guide in
            let text = [guide.title, guide.summary, guide.category, guide.id].joined(separator: " ").lowercased()
            return terms.allSatisfy { text.contains($0) }
        }
    }

    private func filter() {
        shown = Self.matching(field.stringValue, history: history)
        count.stringValue = shown.count == 1 ? T("1 guide", "1 guia") : T("\(shown.count) guides", "\(shown.count) guias")
        let cards = shown.map(card)
        let rows = PanelGrid.rows(cards, columns: 3, gap: MP.Page.gap)
        grid.setViews(rows.isEmpty ? [PanelScreen.note(T("No guide matches.", "Nenhum guia encontrado."))] : rows, in: .top)
        for row in rows { row.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true }
    }

    private func card(_ guide: PanelGuide) -> NSView {
        let category = PanelScreen.label(guide.category)
        let title = PanelText.line(guide.title + " ↗", size: MP.Table.Row.fontSize, color: MP.Link.color, weight: DesignTokens.FontWeight.semibold)
        let summary = PanelText.line(guide.summary, size: DesignTokens.FontSize.meta, color: MP.Head.meta)
        summary.toolTip = guide.summary
        let column = PanelText.column([category, title, summary], gap: 4)
        for view in [title, summary] { view.widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor).isActive = true }
        let press = PanelPress()
        press.box(bg: MP.Box.bg, border: MP.Box.border, radius: MP.Box.radius)
        press.hold(column, padding: MP.Box.padding)
        press.onPress = { [weak self] in self?.open(guide) }
        press.setAccessibilityElement(true)
        press.setAccessibilityRole(.link)
        press.setAccessibilityLabel(guide.title)
        press.setAccessibilityHelp(guide.summary)
        return press
    }

    /// For tests.
    func type(_ words: String) { field.stringValue = words; filter() }
}
