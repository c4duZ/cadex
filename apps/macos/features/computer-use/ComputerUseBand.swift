import AppKit
import Strings

/// The band on top of the screen while the agent acts in another app
/// (docs/spec/computer-use.md): where it acts, and Stop. A panel that never
/// takes the focus; it goes a few seconds after the last action.
@MainActor
final class ComputerUseBand {
    private var panel: NSPanel?
    private let label = NSTextField(labelWithString: "")
    private let stop: () -> Void
    private var hideWork: DispatchWorkItem?

    init(stop: @escaping () -> Void) { self.stop = stop }

    func show(_ text: String) {
        let panel = self.panel ?? make()
        label.stringValue = text
        if let screen = NSScreen.main {
            let size = NSSize(width: 360, height: 34)
            panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 8,
                                  width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        // 15 s, not 4: an agent acting every few seconds made the band blink
        // away before the owner could reach Stop (2026-11-15).
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        panel?.orderOut(nil)
    }

    private func make() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.92).cgColor
        box.layer?.cornerRadius = 10
        label.textColor = .white
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        let button = FirstClickButton(title: T("Stop", "Parar"), target: self, action: #selector(stopPressed))
        button.bezelStyle = .rounded
        let row = NSStackView(views: [label, button])
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 4, left: 14, bottom: 4, right: 6)
        row.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: box.leadingAnchor), row.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            row.topAnchor.constraint(equalTo: box.topAnchor), row.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        panel.contentView = box
        self.panel = panel
        return panel
    }

    @objc private func stopPressed() { stop() }
}

/// Stop works on the first click: the agent's app is in front and Cadex is
/// not, and a plain button's first click only woke the panel; the owner
/// pressed Stop and the agent went on (2026-11-15).
private final class FirstClickButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
