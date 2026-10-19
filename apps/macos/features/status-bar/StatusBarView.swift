import AppKit

/// The bar at the bottom of the window: the focused terminal's folder as a
/// trail of pieces, each with a menu of its subfolders, and the environment
/// on the right (docs/spec/status-bar.md).
public final class StatusBarView: NSView {
    public static let height: CGFloat = 26

    public struct Style {
        public var text: NSColor
        public var secondaryText: NSColor

        public init(text: NSColor, secondaryText: NSColor) {
            self.text = text
            self.secondaryText = secondaryText
        }
    }

    public var style = Style(text: .labelColor, secondaryText: .secondaryLabelColor) { didSet { rebuild() } }
    /// The folder shown; nil while unknown.
    public var path: String? { didSet { if path != oldValue { rebuild() } } }
    /// Whether picking a folder may move the terminal (the shell is idle).
    public var canNavigate = true
    /// A folder picked in a piece's menu.
    public var onNavigate: ((String) -> Void)?

    private let trail = NSStackView()
    private let environment = NSTextField(labelWithString: "Local")
    private let home = NSHomeDirectory()

    public override init(frame: NSRect) {
        super.init(frame: frame)
        trail.orientation = .horizontal
        trail.spacing = 2
        for view in [trail, environment] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            trail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            trail.centerYAnchor.constraint(equalTo: centerYAnchor),
            trail.trailingAnchor.constraint(lessThanOrEqualTo: environment.leadingAnchor, constant: -12),
            environment.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            environment.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("StatusBarView is created in code") }

    private func rebuild() {
        environment.font = .systemFont(ofSize: 11)
        environment.textColor = style.secondaryText
        trail.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let path else { return }
        let segments = Breadcrumb.segments(of: path, home: home)
        for (i, segment) in segments.enumerated() {
            if i > 0 { trail.addArrangedSubview(label("›", color: style.secondaryText)) }
            trail.addArrangedSubview(button(for: segment, last: i == segments.count - 1))
        }
    }

    private func label(_ text: String, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = color
        return label
    }

    private func button(for segment: Breadcrumb.Segment, last: Bool) -> NSView {
        guard let folder = segment.path else { return label(segment.title, color: style.secondaryText) }
        let button = NSButton(title: segment.title, target: self, action: #selector(pieceClicked(_:)))
        button.isBordered = false
        button.attributedTitle = NSAttributedString(string: segment.title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: last ? .semibold : .regular),
            .foregroundColor: last ? style.text : style.secondaryText,
        ])
        button.identifier = NSUserInterfaceItemIdentifier(folder)
        return button
    }

    @objc private func pieceClicked(_ sender: NSButton) {
        guard let folder = sender.identifier?.rawValue else { return }
        let menu = NSMenu()
        if let names = Breadcrumb.subfolders(of: folder) {
            if names.isEmpty { menu.addItem(withTitle: "Sem subpastas", action: nil, keyEquivalent: "").isEnabled = false }
            for name in names {
                let item = NSMenuItem(title: name, action: #selector(folderPicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = (folder as NSString).appendingPathComponent(name)
                item.isEnabled = canNavigate
                menu.addItem(item)
            }
        } else {
            menu.addItem(withTitle: "Sem acesso", action: nil, keyEquivalent: "").isEnabled = false
        }
        menu.autoenablesItems = false
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func folderPicked(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? String else { return }
        onNavigate?(folder)
    }
}
