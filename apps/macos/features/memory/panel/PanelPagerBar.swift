import AppKit
import Strings
import UILooks

/// The page bar of a list (components.memoryPanel.pager; MemorySession.dc.html): « Primeira,
/// ‹ Anterior, "1–50 de 882", Próxima ›, Última », and at the right "Ir para" with the slider, the
/// number and "Ir". A button with nowhere to go is grey; `go` gets the offset.
@MainActor
final class PanelPagerBar: NSView {
    typealias PG = MP.Pager
    let pager: PanelPager
    private let go: (Int) -> Void
    private let slider = NSSlider()
    private let field = NSTextField()
    private(set) var buttons: [String: PanelPress] = [:]

    init(_ pager: PanelPager, go: @escaping (Int) -> Void) {
        self.pager = pager
        self.go = go
        super.init(frame: .zero)
        let range = PanelText.line(pager.range, size: PG.fontSize, color: PG.current, weight: DesignTokens.FontWeight.semibold)
        var views: [NSView] = [button("first", "« " + T("First", "Primeira"), pager.first), button("previous", "‹ " + T("Previous", "Anterior"), pager.previous),
                               range, button("next", T("Next", "Próxima") + " ›", pager.next), button("last", T("Last", "Última") + " »", pager.last),
                               PanelText.spring()]
        if pager.total > pager.limit {
            slider.minValue = 1
            slider.maxValue = Double(pager.total)
            slider.integerValue = pager.offset + 1
            slider.target = self
            slider.action = #selector(slid)
            slider.widthAnchor.constraint(equalToConstant: UILooks.pt(PG.Slider.width)).isActive = true
            slider.setAccessibilityLabel(T("Go to", "Ir para"))
            field.stringValue = String(pager.offset + 1)
            field.font = UILooks.font(MP.Field.fontSize)
            field.alignment = .right
            field.target = self
            field.action = #selector(jump)
            field.widthAnchor.constraint(equalToConstant: UILooks.pt(MP.Field.height + MP.Field.height)).isActive = true
            field.setAccessibilityLabel(T("Observation number", "Número da observação"))
            let goButton = DesignButton.make(T("Go", "Ir"), .secondary) { [weak self] in self?.jump() }
            views += [PanelText.line(T("Go to", "Ir para"), size: PG.fontSize, color: PG.color), slider, field, goButton]
        }
        let row = PanelText.row(views, gap: PG.gap)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(pager.range)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelPagerBar is created in code") }

    private func button(_ key: String, _ title: String, _ offset: Int?) -> NSView {
        let press = PanelPress()
        let label = PanelText.line(title, size: PG.fontSize, color: offset == nil ? PG.color : MP.Link.color,
                                   weight: offset == nil ? .regular : MP.Link.weight)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        press.hold(label, padding: NSEdgeInsets())
        if let offset { press.onPress = { [weak self] in self?.go(offset) } }
        press.setAccessibilityElement(true)
        press.setAccessibilityRole(.button)
        press.setAccessibilityLabel(title)
        press.setAccessibilityEnabled(offset != nil)
        buttons[key] = press
        return press
    }

    @objc private func slid() { field.integerValue = slider.integerValue }

    /// "Ir": the page with that observation.
    @objc func jump() {
        let n = Int(field.stringValue.trimmingCharacters(in: .whitespaces)) ?? pager.offset + 1
        let offset = pager.offset(ofItem: n)
        if offset != pager.offset { go(offset) }
    }

    /// For tests.
    func press(_ key: String) { buttons[key]?.onPress?() }
    func type(_ n: Int) {
        field.stringValue = String(n)
        jump()
    }
}
