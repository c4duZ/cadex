import AppKit
import Menus
import Strings
import UILooks

/// The Folder item: the focused terminal's folder as a trail of pieces,
/// "Home › Cadu › Trabalho › cadex", each with a menu of its subfolders
/// (docs/spec/status-bar.md, Folder). It is rebuilt only when the folder
/// changes, never on the terminal's output.
@MainActor
final class FolderTrail: NSView {
    var path: String? { didSet { if path != oldValue { rebuild() } } }
    var canNavigate = true
    var onNavigate: ((String) -> Void)?
    var colors: (text: NSColor, secondary: NSColor) = (.labelColor, .secondaryLabelColor) { didSet { restyle() } }
    private let trail = NSStackView()
    private let home = NSHomeDirectory()

    init() {
        super.init(frame: .zero)
        trail.orientation = .horizontal
        trail.spacing = 2
        // A long path is cut, it does not hold the window's width: its
        // pieces resisted shrinking and kept the window from getting
        // narrower (owner, 2026-10-19).
        trail.setClippingResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        trail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trail)
        NSLayoutConstraint.activate([
            // The bar's items keep 6 pt around them (StatusBarView.itemInset).
            trail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: StatusBarView.itemInset),
            // As wide as its pieces, so an item after it sits right after it
            // (with "less or equal" the trail stretched and pushed it away).
            trail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -StatusBarView.itemInset),
            trail.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: UILooks.pt(20)),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("FolderTrail is created in code") }

    private func rebuild() {
        SlidingStack.fade(self)
        trail.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let path else { return }
        let segments = Breadcrumb.segments(of: path, home: home)
        for (i, segment) in segments.enumerated() {
            if i > 0 { trail.addArrangedSubview(label("›")) }
            trail.addArrangedSubview(button(for: segment, last: i == segments.count - 1))
        }
    }

    /// A theme change repaints the pieces in place: rebuilding them left
    /// AppKit's bookkeeping of every new button behind, ~8 KB per theme
    /// change (measured 2026-10-20).
    private func restyle() {
        let pieces = trail.arrangedSubviews
        for (i, view) in pieces.enumerated() {
            if let button = view as? NSButton {
                button.attributedTitle = title(button.attributedTitle.string, last: i == pieces.count - 1)
            } else if let label = view as? NSTextField {
                label.textColor = colors.secondary
            }
        }
    }

    private func title(_ text: String, last: Bool) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: UILooks.font(11, weight: last ? .semibold : .regular),
            .foregroundColor: last ? colors.text : colors.secondary,
        ])
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = UILooks.font(11)
        label.textColor = colors.secondary
        return label
    }

    private func button(for segment: Breadcrumb.Segment, last: Bool) -> NSView {
        guard let folder = segment.path else { return label(segment.title) }
        let button = NSButton(title: segment.title, target: self, action: #selector(pieceClicked(_:)))
        button.isBordered = false
        button.attributedTitle = title(segment.title, last: last)
        button.identifier = NSUserInterfaceItemIdentifier(folder)
        return button
    }

    @objc private func pieceClicked(_ sender: NSButton) {
        guard let folder = sender.identifier?.rawValue else { return }
        var entries: [MenuEntry]
        if let names = Breadcrumb.subfolders(of: folder) {
            entries = names.map { name in
                let path = (folder as NSString).appendingPathComponent(name)
                return MenuEntry(name, icon: .folder, isEnabled: canNavigate) { [weak self] in self?.onNavigate?(path) }
            }
            if names.isEmpty { entries = [MenuEntry(T("No subfolders", "Sem subpastas"), isEnabled: false) {}] }
        } else {
            entries = [MenuEntry(T("No access", "Sem acesso"), isEnabled: false) {}]
        }
        // Above the bar: it sits at the bottom of the window.
        PopupMenu.show(entries, above: sender)
    }
}
