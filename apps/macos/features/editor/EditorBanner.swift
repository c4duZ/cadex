import AppKit
import UILooks

/// A strip at the top of an editor tab for notes that need attention: a
/// big file shown in part, a change on disk, a failed save.
final class EditorBanner: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")
    private let buttons = NSStackView()
    private var actions: [() -> Void] = []
    private var height: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.18).cgColor
        label.font = UILooks.font(12)
        buttons.spacing = 6
        let row = NSStackView(views: [label, buttons])
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        height = heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            height,
        ])
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("EditorBanner is created in code") }

    func show(_ text: String, actions list: [(String, () -> Void)] = []) {
        label.stringValue = text
        buttons.arrangedSubviews.forEach { $0.removeFromSuperview() }
        actions = list.map(\.1)
        for (i, item) in list.enumerated() {
            let button = NSButton(title: item.0, target: self, action: #selector(run(_:)))
            button.tag = i
            button.bezelStyle = .rounded
            button.controlSize = .small
            buttons.addArrangedSubview(button)
        }
        isHidden = false
        height.constant = 30
    }

    func hide() {
        isHidden = true
        height.constant = 0
    }

    @objc private func run(_ sender: NSButton) {
        guard sender.tag < actions.count else { return }
        actions[sender.tag]()
    }
}

/// Instead of the text: a binary file, an error, with an optional button.
final class EditorMessageView: NSView {
    private let action: () -> Void

    init(text: String, action title: String?, run: @escaping () -> Void) {
        action = run
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: text)
        label.font = UILooks.font(14)
        label.textColor = .secondaryLabelColor
        var views: [NSView] = [label]
        if let title { views.append(NSButton(title: title, target: self, action: #selector(press))) }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("EditorMessageView is created in code") }

    @objc private func press() { action() }
}
