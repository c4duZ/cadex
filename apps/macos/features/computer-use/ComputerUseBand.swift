import AppKit
import AgentBand
import Strings

/// The band on top of the screen while the agent acts in another app
/// (docs/spec/computer-use.md): where it acts, and Stop. A panel that never
/// takes the focus, showing `AgentBandView`; it goes 15 s after the last action.
@MainActor
final class ComputerUseBand {
    private var panel: NSPanel?
    private static let margin: CGFloat = 14
    private let view: AgentBandView
    private var hideWork: DispatchWorkItem?

    init(stop: @escaping () -> Void) {
        view = AgentBandView(trailing: .button(T("Stop", "Parar"), stop), inWindow: false)
    }

    func show(_ text: String) {
        let panel = self.panel ?? make()
        view.text = text
        if let screen = NSScreen.main {
            // Room around the pill for its shadow, which the panel would cut.
            let size = NSSize(width: view.fittingSize.width + 2 * Self.margin, height: AgentBandView.height + 2 * Self.margin)
            panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 4,
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
        panel.isOpaque = false
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        let content = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        panel.contentView = content
        self.panel = panel
        return panel
    }
}
