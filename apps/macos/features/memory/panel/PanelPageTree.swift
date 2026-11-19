import AppKit
import Icons
import Strings
import UILooks

/// PÁGINAS in the Conhecimento tab (MemoryProject.dc.html): a line per folder with its count, a
/// click opens it to its pages (newest first), a click on a page opens it; "Sistema" holds the
/// machinery folders, dimmer (upstream's `is_system_page`). The arrows keys are the outline's.
@MainActor
final class PanelPageTree: NSView {
    private let knowledge: PanelKnowledge
    private let open: (String) -> Void
    private let stack = PanelText.column([], gap: 0)
    private(set) var expanded: Set<String> = []
    private(set) var systemShown = true

    init(_ knowledge: PanelKnowledge, open: @escaping (String) -> Void) {
        self.knowledge = knowledge
        self.open = open
        super.init(frame: .zero)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.outline)
        setAccessibilityLabel(T("Pages", "Páginas"))
        draw()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelPageTree is created in code") }

    private func draw() {
        var views: [NSView] = [PanelScreen.label(T("Pages", "Páginas"))]
        if knowledge.folders.isEmpty && knowledge.system.isEmpty {
            views.append(PanelText.line(T("No compiled page yet.", "Nenhuma página compilada ainda."), size: MP.Empty.Text.fontSize, color: MP.Empty.Text.color))
        }
        for folder in knowledge.folders { views += lines(folder, dim: false) }
        if !knowledge.system.isEmpty {
            views.append(row(T("System", "Sistema"), count: nil, caret: systemShown, dim: true, indent: false) { [weak self] in
                self?.systemShown.toggle()
                self?.draw()
            })
            if systemShown { for folder in knowledge.system { views += lines(folder, dim: true) } }
        }
        stack.setViews(views, in: .top)
        for view in views.dropFirst() { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        stack.setCustomSpacing(UILooks.pt(MP.Chip.gap), after: views[0])
    }

    private func lines(_ folder: PanelFolder, dim: Bool) -> [NSView] {
        let key = (dim ? "system/" : "") + folder.name
        let open = expanded.contains(key)
        var out = [row(folder.name == PanelKnowledge.rootFolder ? folder.name : folder.name + "/", count: folder.count, caret: open, dim: dim, indent: false) {
            [weak self] in
            if self?.expanded.remove(key) == nil { self?.expanded.insert(key) }
            self?.draw()
        }]
        if open {
            for page in folder.pages {
                out.append(row(page.title, count: nil, caret: nil, dim: dim, indent: true) { [weak self] in self?.open(page.path) })
            }
        }
        return out
    }

    /// One line: "▸ decisions/ … 1", or a page's title under its folder.
    private func row(_ title: String, count: Int?, caret: Bool?, dim: Bool, indent: Bool, press: @escaping () -> Void) -> NSView {
        typealias R = MP.Nav.Row
        let color = dim ? MP.Head.meta : DesignTokens.Color.textRow
        var views: [NSView] = []
        if let caret {
            let glyph = NSImageView(image: (caret ? Icon.caretDown : Icon.caretRight).image(size: UILooks.pt(MP.Chip.dot + MP.Chip.dot)))
            glyph.contentTintColor = MP.Breadcrumb.color
            views.append(glyph)
        }
        views.append(PanelText.line(title, size: R.fontSize, color: indent ? MP.Link.color : color))
        views.append(PanelText.spring())
        if let count { views.append(PanelText.line(PanelWords.number(count), size: DesignTokens.FontSize.meta, color: MP.Head.meta)) }
        let line = PanelPress()
        var padding = R.padding
        if indent { padding.left += R.icon + R.gap }
        line.hold(PanelText.row(views, gap: MP.Chip.gap), padding: padding)
        line.heightAnchor.constraint(equalToConstant: UILooks.rowHeight(R.height)).isActive = true
        line.onPress = press
        line.onHover = { [weak line] on in line?.box(bg: on ? R.Selected.bg : nil, border: nil, radius: R.radius) }
        line.setAccessibilityElement(true)
        line.setAccessibilityRole(caret == nil ? .link : .disclosureTriangle)
        line.setAccessibilityLabel(title)
        if let caret { line.setAccessibilityValue(caret ? 1 : 0) }
        return line
    }

    /// For tests: the lines' words in order.
    var lineTitles: [String] {
        stack.arrangedSubviews.dropFirst().compactMap { ($0 as? PanelPress)?.accessibilityLabel() }
    }
    func press(_ title: String) {
        (stack.arrangedSubviews.first { ($0 as? PanelPress)?.accessibilityLabel() == title } as? PanelPress)?.onPress?()
    }
}
