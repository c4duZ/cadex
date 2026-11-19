import AppKit
import Menus
import Strings
import UILooks

/// The filters of the token box (upstream's `calls_*` query; MemorySession.dc.html: the ten fields
/// go to "Filtrar…", a popover with the same fields).
public struct PanelTokenFilter: Equatable, Sendable {
    public var values: [String: String] = [:]
    public init() {}

    /// The fields, upstream's names and order: (query name, title, placeholder).
    static var fields: [(key: String, title: String, hint: String)] {
        [("calls_q", T("Search", "Busca"), T("Model, agent or response", "Modelo, agente ou resposta")),
         ("calls_signal", T("Responses", "Respostas"), "all | signals"),
         ("calls_sort", T("Order", "Ordem"), "tokens | recent"),
         ("calls_from", T("From (UTC)", "De (UTC)"), "2026-11-19T10:00"),
         ("calls_until", T("Until (UTC)", "Até (UTC)"), "2026-11-20"),
         ("calls_model", T("Model", "Modelo"), T("All models", "Todos os modelos")),
         ("calls_agent", T("Agent client", "Cliente de agente"), "claude-code"),
         ("calls_session", T("Session ID", "ID da sessão"), T("All sessions", "Todas as sessões")),
         ("calls_turn", T("Turn ID", "ID do turno"), T("All turns", "Todos os turnos")),
         ("calls_tool", T("Tool", "Ferramenta"), T("All tools", "Todas as ferramentas"))]
    }

    /// `?calls_q=…&…` for the route, the empty ones left out; "" with none.
    public var query: String {
        let pairs = values.keys.sorted().compactMap { key -> String? in
            let value = values[key]!.trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : key + "=" + PanelPath.value(value)
        }
        return pairs.isEmpty ? "" : "?" + pairs.joined(separator: "&")
    }
}

/// "Uso de tokens" (MemorySession.dc.html; upstream's usage panel): the title, "Durante as sessões",
/// the counts line and "Filtrar…"; the six numbers; the responses' table, or the empty line with ⓘ.
@MainActor
final class PanelTokensBox: NSView {
    let report: PanelTokenReport
    private var filter: PanelTokenFilter
    private let apply: (PanelTokenFilter) -> Void
    private let popover = AnchoredPanel()
    private(set) var filterButton: NSButton?

    init(_ report: PanelTokenReport, filter: PanelTokenFilter, apply: @escaping (PanelTokenFilter) -> Void) {
        self.report = report
        self.filter = filter
        self.apply = apply
        super.init(frame: .zero)
        let rows = [head(), PanelScreen.rule(), numbers(), PanelScreen.rule(), foot()]
        let column = PanelText.column(rows, gap: 0)
        for row in rows { row.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        let box = PanelScreen.box(column, padding: NSEdgeInsets())
        box.translatesAutoresizingMaskIntoConstraints = false
        addSubview(box)
        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: topAnchor), box.bottomAnchor.constraint(equalTo: bottomAnchor),
            box.leadingAnchor.constraint(equalTo: leadingAnchor), box.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(T("Token usage", "Uso de tokens"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelTokensBox is created in code") }

    private func head() -> NSView {
        let title = PanelText.line(T("Token usage", "Uso de tokens"), size: DesignTokens.FontSize.body, color: DesignTokens.Color.textPrimary,
                                   weight: DesignTokens.FontWeight.semibold)
        let line = PanelText.line(PanelWords.tokenLine(report), size: DesignTokens.FontSize.meta, color: MP.Head.meta)
        let button = DesignButton.make(filter.values.isEmpty ? T("Filter…", "Filtrar…") : T("Filtered…", "Filtrado…"), .secondary) { [weak self] in
            self?.toggleFilter()
        }
        filterButton = button
        return holder(PanelText.row([title, PanelChip.make(T("During sessions", "Durante as sessões"), .green), PanelText.spring(), line, button],
                                    gap: MP.Head.gap), MP.Box.padding)
    }

    private func numbers() -> NSView {
        let fromCache: String = {
            let total = report.input + report.cacheRead + report.cacheWrite
            return total > 0 ? "\(Int((Double(report.cacheRead) / Double(total) * 100).rounded()))%" : "—"
        }()
        let items = [(T("Captured calls", "Chamadas capturadas"), PanelWords.number(report.callCount)),
                     (T("Fresh input", "Entrada nova"), PanelWords.tokens(report.input)), (T("Output", "Saída"), PanelWords.tokens(report.output)),
                     (T("Cache read", "Leitura do cache"), PanelWords.tokens(report.cacheRead)),
                     (T("Cache write", "Gravação no cache"), PanelWords.tokens(report.cacheWrite)), (T("Input from cache", "Entrada do cache"), fromCache)]
        let cells = items.map { title, value -> NSView in
            let column = PanelText.column([PanelText.line(title, size: MP.Stat.Label.fontSize, color: MP.Stat.Label.color),
                                           PanelText.line(value, size: DesignTokens.FontSize.sheetTitle, color: DesignTokens.Color.textPrimary,
                                                          weight: DesignTokens.FontWeight.semibold)], gap: MP.Stat.gap)
            column.setAccessibilityElement(true)
            column.setAccessibilityLabel(title + " " + value)
            return holder(column, MP.Box.padding)
        }
        let row = NSStackView(views: cells)
        row.distribution = .fillEqually
        row.spacing = 0
        return row
    }

    private func foot() -> NSView {
        guard !report.calls.isEmpty else {
            let empty = report.callCount > 0 ? T("No captured response matches these filters", "Nenhuma resposta capturada corresponde a estes filtros")
                : T("No response usage reported yet", "Nenhum uso de resposta informado ainda")
            let help = PanelHelpButton(T("Updated Claude Code and Codex clients report usage per response; existing session totals stay visible. Dates use the reported response time when there is one. Usage not reported is unknown, never zero.",
                                         "Clientes atualizados do Claude Code e do Codex informam o uso de cada resposta; os totais das sessões existentes continuam visíveis. As datas usam o horário informado da resposta quando há. Uso não informado é desconhecido, nunca zero."))
            return holder(PanelText.row([PanelText.line(empty, size: DesignTokens.FontSize.meta, color: MP.Head.meta), help, PanelText.spring()],
                                        gap: MP.Chip.gap), MP.Box.padding)
        }
        let table = PanelTable([PanelColumn(title: T("Response / session", "Resposta / sessão"), share: 0.2),
                                PanelColumn(title: T("Model", "Modelo"), share: 0.18), PanelColumn(title: T("Input", "Entrada"), share: 0.1),
                                PanelColumn(title: T("Output", "Saída"), share: 0.1), PanelColumn(title: "Cache", share: 0.1),
                                PanelColumn(title: "Total", share: 0.1), PanelColumn(title: T("Signal", "Sinal"), share: nil)])
        typealias R = MP.Table.Row
        table.show(report.calls.map { c in
            [PanelText.line(PanelWords.shortID(c.session), size: R.fontSize, color: R.color), PanelText.line(c.model, size: R.fontSize, color: R.color),
             PanelText.line(PanelWords.tokens(c.input), size: R.fontSize, color: R.color), PanelText.line(PanelWords.tokens(c.output), size: R.fontSize, color: R.color),
             PanelText.line(PanelWords.tokens(c.cache), size: R.fontSize, color: R.color), PanelText.line(PanelWords.tokens(c.total), size: R.fontSize, color: R.color),
             PanelText.line(c.signal ?? "—", size: R.fontSize, color: c.signal == nil ? R.color : MP.Notice.title)]
        })
        return table
    }

    private func holder(_ view: NSView, _ padding: NSEdgeInsets) -> NSView {
        let box = FrameBox()
        box.hold(view, padding: padding)
        return box
    }

    // MARK: Filtrar…

    private var fields: [String: NSTextField] = [:]

    func toggleFilter() {
        guard let filterButton else { return }
        if popover.isOpen { return popover.close() }
        var rows: [[NSView]] = []
        for field in PanelTokenFilter.fields {
            let input = NSTextField()
            input.font = UILooks.font(MP.Field.fontSize)
            input.placeholderString = field.hint
            input.stringValue = filter.values[field.key] ?? ""
            input.setAccessibilityLabel(field.title)
            fields[field.key] = input
            rows.append([PanelText.line(field.title, size: DesignTokens.FontSize.meta, color: MP.Head.meta), input])
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = UILooks.pt(MP.Chip.gap)
        grid.columnSpacing = UILooks.pt(MP.Table.columnGap)
        grid.column(at: 1).width = UILooks.pt(MP.Field.width)
        let clear = DesignButton.make(T("Clear", "Limpar"), .secondary) { [weak self] in self?.submit(PanelTokenFilter()) }
        let search = DesignButton.make(T("Search", "Pesquisar"), .primary) { [weak self] in self?.submitFields() }
        let column = PanelText.column([grid, PanelText.row([PanelText.spring(), clear, search], gap: MP.Chip.gap)], gap: MP.Page.gap)
        column.arrangedSubviews.last?.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        let box = FrameBox()
        box.hold(column, padding: MP.Box.padding)
        popover.show(box, below: filterButton, width: UILooks.pt(MP.Field.width + MP.Aside.width))
    }

    private func submitFields() {
        var next = PanelTokenFilter()
        for (key, field) in fields where !field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty { next.values[key] = field.stringValue }
        submit(next)
    }

    private func submit(_ next: PanelTokenFilter) {
        popover.close()
        filter = next
        apply(next)
    }

    /// For tests.
    var filterShowing: Bool { popover.isOpen }
}
