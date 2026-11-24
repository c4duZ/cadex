import AppKit
import Icons
import Strings

/// Over Claude's pinned foot (ClaudeFootPin) while the history scrolls: a hairline between the
/// history and the foot, and "Back to bottom" at its right end, which runs terminal.scroll-bottom
/// (the owner, 2026-11-24, as Claude's fullscreen mode has its "Jump to bottom"). Only the button
/// takes clicks; the line lets them through to the terminal.
final class TerminalFootDivider: NSView {
    private let line = NSView()
    private let pill = NSView()
    private let button: NSButton
    private let act: () -> Void
    static let height: CGFloat = 24

    init(act: @escaping () -> Void) {
        self.act = act
        button = NSButton(title: T("Back to bottom", "Voltar ao fim"), target: nil, action: nil)
        super.init(frame: .zero)
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        pill.wantsLayer = true
        pill.layer?.cornerRadius = Self.height / 2
        pill.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        pill.layer?.borderWidth = 0.5
        pill.layer?.borderColor = NSColor.separatorColor.cgColor
        button.isBordered = false
        button.image = Icon.arrowDown.image(size: 12)
        button.imagePosition = .imageLeading
        button.contentTintColor = .secondaryLabelColor
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.target = self
        button.action = #selector(pressed)
        button.toolTip = T("Scroll to the bottom", "Ir ao fim do histórico")
        for view in [line, pill, button] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(line)
        addSubview(pill)
        pill.addSubview(button)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
            pill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: Self.height),
            button.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 10),
            button.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -10),
            button.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TerminalFootDivider is created in code") }

    @objc private func pressed() { act() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === button || hit?.isDescendant(of: pill) == true ? hit : nil
    }
}

extension TerminalView {
    /// The divider where the last frame pinned Claude's foot, or none when nothing is pinned.
    func placeFootDivider() {
        guard let from = renderer?.pinnedFrom, let metrics = renderer?.metrics else {
            footDivider?.removeFromSuperview()
            footDivider = nil
            return
        }
        let divider = footDivider ?? TerminalFootDivider { [weak self] in self?.backToBottom() } as NSView
        if divider.superview !== self { addSubview(divider, positioned: .above, relativeTo: canvas) }
        footDivider = divider
        // In the empty part of the box's top rule row, above the box (it starts two thirds in).
        let cell = CGFloat(metrics.height) / (window?.backingScaleFactor ?? 2)
        let fromTop = geometry.padding + CGFloat(from) * cell + cell * 0.3
        divider.frame = NSRect(x: 0, y: bounds.height - fromTop - TerminalFootDivider.height / 2,
                               width: bounds.width, height: TerminalFootDivider.height)
    }

    /// "Back to bottom": terminal.scroll-bottom on this terminal (ADR 0005), focused first.
    private func backToBottom() {
        window?.makeFirstResponder(self)
        if runCommand?("terminal.scroll-bottom") != true { terminalScrollToBottom(nil) }
    }
}
