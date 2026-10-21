import AppKit
import UILooks

/// A page's sub-tabs beside its title (Agents: Sessions, Accounts): words
/// in the theme's colors, the picked one on a soft fill. The system's
/// segmented control painted the picked one in the system's blue, apart
/// from the theme (the owner, 2026-10-21).
@MainActor
final class SidebarSubtabs: NSView {
    var onPick: ((Int) -> Void)?
    var colors = SidebarColors() { didSet { restyle() } }
    private(set) var selected = 0
    private let stack = NSStackView()
    private var labels: [NSTextField] = []

    init() {
        super.init(frame: .zero)
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SidebarSubtabs is created in code") }

    override var mouseDownCanMoveWindow: Bool { false }

    func set(_ titles: [String], selected: Int) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        labels = titles.map { title in
            let label = NSTextField(labelWithString: title)
            label.font = UILooks.font(11, weight: .medium)
            label.alignment = .center
            label.wantsLayer = true
            label.layer?.cornerRadius = 5
            label.translatesAutoresizingMaskIntoConstraints = false
            label.setAccessibilityRole(.radioButton)
            return label
        }
        for label in labels {
            let box = NSView()
            box.wantsLayer = true
            box.layer?.cornerRadius = 5
            box.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 7),
                label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -7),
                label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
                box.heightAnchor.constraint(equalToConstant: UILooks.pt(20)),
            ])
            stack.addArrangedSubview(box)
        }
        self.selected = selected
        restyle()
    }

    func select(_ index: Int) {
        selected = index
        restyle()
    }

    private func restyle() {
        for (index, label) in labels.enumerated() {
            let on = index == selected
            label.textColor = on ? colors.text : colors.secondary
            label.superview?.layer?.backgroundColor = on ? colors.fill.cgColor : nil
            label.setAccessibilityValue(on)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = stack.arrangedSubviews.firstIndex(where: { $0.frame.contains(stack.convert(point, from: self)) }) else { return }
        select(index)
        onPick?(index)
    }
}
