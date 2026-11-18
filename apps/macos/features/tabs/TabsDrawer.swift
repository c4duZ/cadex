import AppKit
import Icons
import Strings
import UILooks

/// The terminal drawer (plan 30 C; the Drawer mockup): quick terminals that are no project's,
/// rising from the bottom over the center, 340 pt tall with a shadow up. Its header has its own
/// tabs (a TabsController of its own: `tabs`), "+" and the hint; its top edge drags to resize.
@MainActor
public final class DrawerView: NSView {
    typealias D = DesignTokens.Drawer
    public let tabs: TabsController
    /// The drawer's height, kept while the app runs.
    public private(set) var height = UILooks.pt(D.height)
    /// The height changed by a drag: the host lays it out again.
    public var onResize: (() -> Void)?
    private let header = NSView()
    private let hint = NSTextField(labelWithString: "")
    private let plus = NSButton()

    public init(tabs: TabsController, hint words: String) {
        self.tabs = tabs
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = D.bg.cgColor
        if let shadow = D.shadow.first {
            layer?.masksToBounds = false
            layer?.shadowColor = shadow.color.cgColor
            layer?.shadowOpacity = 1
            layer?.shadowRadius = UILooks.pt(shadow.layerRadius)
            layer?.shadowOffset = shadow.offset
        }
        hint.stringValue = words
        hint.font = UILooks.font(D.Hint.fontSize)
        hint.textColor = D.Hint.color
        hint.lineBreakMode = .byTruncatingHead
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        plus.image = Icon.plus.image(size: UILooks.pt(D.Tabs.Tab.fontSize))
        plus.isBordered = false
        plus.contentTintColor = D.Hint.color
        plus.setAccessibilityLabel(T("New terminal in the drawer", "Novo terminal na gaveta"))
        plus.target = self
        plus.action = #selector(newTab)
        let bar = tabs.bar
        for view in [header, tabs.view, bar, plus, hint] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(header)
        addSubview(tabs.view)
        header.addSubview(bar)
        header.addSubview(plus)
        header.addSubview(hint)
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = D.borderTop.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        let pad = D.Tabs.padding
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: topAnchor), line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor), line.heightAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline),
            header.topAnchor.constraint(equalTo: topAnchor), header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor), header.heightAnchor.constraint(equalToConstant: UILooks.pt(D.Tabs.height)),
            bar.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: UILooks.pt(pad.left)),
            bar.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            bar.heightAnchor.constraint(equalToConstant: UILooks.pt(D.Tabs.Tab.height)),
            plus.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: UILooks.pt(D.Tabs.gap)),
            plus.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            hint.leadingAnchor.constraint(greaterThanOrEqualTo: plus.trailingAnchor, constant: UILooks.pt(D.Tabs.gap)),
            hint.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -UILooks.pt(pad.right)),
            hint.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            tabs.view.topAnchor.constraint(equalTo: header.bottomAnchor),
            tabs.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabs.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabs.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        bar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("DrawerView is created in code") }

    public override var isFlipped: Bool { true }

    @objc private func newTab() { tabs.newTab() }

    // MARK: Resizing by the top edge

    private var dragFrom: (y: CGFloat, height: CGFloat)?

    public override func resetCursorRects() {
        addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: UILooks.pt(D.grip)), cursor: .resizeUpDown)
    }

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard point.y < UILooks.pt(D.grip) else { return super.mouseDown(with: event) }
        dragFrom = (event.locationInWindow.y, height)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let from = dragFrom else { return super.mouseDragged(with: event) }
        let limit = (superview?.bounds.height ?? 800) - UILooks.pt(D.Tabs.height) * 2
        height = min(max(from.height + event.locationInWindow.y - from.y, UILooks.pt(D.minHeight)), max(limit, UILooks.pt(D.minHeight)))
        onResize?()
    }

    public override func mouseUp(with event: NSEvent) {
        if dragFrom == nil { super.mouseUp(with: event) }
        dragFrom = nil
    }
}
