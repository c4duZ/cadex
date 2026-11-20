import AppKit
import Strings
import UILooks

/// Grafo de conhecimento (plan 40 E, MemoryGraph.dc.html): the general one, the links between
/// projects, and a project's ("Grafo de links ↗" on the project). The title, the numbers, the
/// graph at the left (PanelGraphCanvas, a force layout), CONEXÕES at the right; a node or a
/// connection opens its page (a project's node, that project's graph).
@MainActor
final class PanelGraphView: PanelScreen {
    typealias G = MP.Graph
    let graph: PanelGraph
    let canvas: PanelGraphCanvas
    private var connectionLinks: [PanelLink] = []

    init(_ graph: PanelGraph, synchronous: Bool = false, go: @escaping (PanelPlace) -> Void) {
        self.graph = graph
        canvas = PanelGraphCanvas(graph, synchronous: synchronous)
        super.init(go: go)
        canvas.onOpen = { [weak self] index in self?.open(index) }
        var parts: [NSView] = []
        if let p = graph.project { parts.append(trail(PanelPlace.graph(p).crumbs)) }
        let title = graph.project.map { T("Link graph of ", "Grafo de links de ") + PanelGraph.name($0) } ?? T("Link graph", "Grafo de links")
        parts.append(heading(title))
        parts.append(summaryRow())
        if graph.truncated { parts.append(cutNotice()) }
        parts.append(body())
        fill(parts)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelGraphView is created in code") }

    private func summaryRow() -> NSView {
        var views: [NSView] = [PanelText.line(graph.summary, size: DesignTokens.FontSize.body, color: MP.Head.meta)]
        if graph.project == nil {
            views.append(PanelHelpButton(T("Resolved wikilinks whose ends sit in different projects. A connection shows only when both ends can be read.",
                                            "Wikilinks resolvidos cujas extremidades estão em projetos diferentes. Uma conexão só aparece quando as duas extremidades podem ser lidas.")))
        }
        views.append(PanelText.spring())
        let row = PanelText.row(views, gap: MP.Chip.gap)
        guard let empty = graph.emptyLine else { return row }
        return PanelText.column([row, PanelScreen.note(empty)], gap: MP.Chip.gap)
    }

    /// Upstream's amber notice when the engine cut the graph at its node cap.
    private func cutNotice() -> NSView {
        let words = PanelText.line(T("Only the \(graph.nodes.count) most linked and newest pages are drawn.",
                                     "Só as \(graph.nodes.count) páginas mais ligadas e mais novas aparecem."), size: DesignTokens.FontSize.meta, color: MP.Notice.text)
        let box = FrameBox()
        box.box(bg: MP.Notice.bg, border: MP.Notice.border, radius: MP.Notice.radius)
        box.hold(PanelText.row([words, PanelText.spring()], gap: 0), padding: MP.Notice.padding)
        return box
    }

    private func body() -> NSView {
        canvas.translatesAutoresizingMaskIntoConstraints = false
        let side = UILooks.pt(G.size)
        canvas.widthAnchor.constraint(equalToConstant: side).isActive = true
        canvas.heightAnchor.constraint(equalToConstant: side).isActive = true
        let left = PanelText.column([canvas, legend()], gap: G.Side.gap)
        let right = connections()
        right.widthAnchor.constraint(equalToConstant: UILooks.pt(G.Side.width)).isActive = true
        let row = NSStackView(views: [left, right, PanelText.spring()])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = UILooks.pt(MP.Page.gap) * 2
        return row
    }

    /// A dot and its kind for each kind drawn; the ring says "sem links" when some are loose.
    private func legend() -> NSView {
        var items: [NSView] = graph.kinds.map { item(PanelGraphCanvas.color($0), $0 == "other" ? T("other", "outro") : $0) }
        if !graph.loose.isEmpty, !graph.edges.isEmpty {
            items.append(item(.clear, T("no links", "sem links"), ring: G.Node.Kind.other))
        }
        return PanelText.row(items + [PanelText.spring()], gap: G.Legend.gap)
    }

    /// `ring`: the loose pages' ring, as the canvas draws them.
    private func item(_ color: NSColor, _ words: String, ring: NSColor? = nil) -> NSView {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = color.cgColor
        dot.layer?.borderColor = ring?.cgColor
        dot.layer?.borderWidth = ring == nil ? 0 : DesignTokens.Stroke.glyph
        dot.layer?.cornerRadius = UILooks.pt(G.Legend.dot) / 2
        dot.widthAnchor.constraint(equalToConstant: UILooks.pt(G.Legend.dot)).isActive = true
        dot.heightAnchor.constraint(equalToConstant: UILooks.pt(G.Legend.dot)).isActive = true
        return PanelText.row([dot, PanelText.line(words, size: G.Legend.fontSize, color: G.Legend.color)], gap: MP.Chip.gap)
    }

    private func connections() -> NSView {
        var views: [NSView] = [PanelScreen.label(T("Connections", "Conexões"))]
        if graph.connections.isEmpty {
            views.append(PanelScreen.note(T("No resolved link.", "Nenhum link resolvido.")))
        }
        for connection in graph.connections {
            let from = PanelLink(connection.from.label, size: DesignTokens.FontSize.meta) { [weak self] in self?.go(.page(connection.from.project, connection.from.path)) }
            let to = PanelLink(connection.to.label, size: DesignTokens.FontSize.meta) { [weak self] in self?.go(.page(connection.to.project, connection.to.path)) }
            connectionLinks += [from, to]
            let arrow = PanelText.line("→", size: DesignTokens.FontSize.meta, color: MP.Head.meta)
            let line = PanelText.column([from, PanelText.row([arrow, to], gap: MP.Chip.gap)], gap: 2)
            line.setAccessibilityElement(true)
            line.setAccessibilityRole(.group)
            line.setAccessibilityLabel(connection.from.label + " → " + connection.to.label)
            views.append(line)
        }
        let column = PanelText.column(views, gap: G.Side.gap)
        for view in views { view.widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor).isActive = true }
        return column
    }

    /// A node: its page, or for a project node, that project's graph.
    private func open(_ index: Int) {
        let node = graph.nodes[index]
        go(node.path.isEmpty ? .graph(node.project) : .page(node.project, node.path))
    }

    override var firstFocus: NSView { canvas.acceptsFirstResponder ? canvas : self }

    /// For tests.
    func pressConnection(_ index: Int) { connectionLinks[index].onPress?() }
}
