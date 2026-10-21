import AppKit
import MetalKit

/// The Metal surface a terminal draws into, there only while the terminal
/// is in a window. A hidden tab's terminal lets go of it, and with it the
/// layer's pool of drawables: ~22 MB per hidden tab that releasing the
/// drawables or shrinking them did not free, as the pool goes only with its
/// layer (make perf, 2026-10-21). Everything else (the session, input,
/// selection, find) stays in the TerminalView, which takes every event: the
/// canvas is never hit, never first responder.
@MainActor
final class TerminalCanvas: MTKView {
    weak var terminal: TerminalView?

    init(terminal: TerminalView, device: MTLDevice) {
        self.terminal = terminal
        super.init(frame: terminal.bounds, device: device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        // Draw on demand: only when the shell sends output or the view changes.
        isPaused = true
        enableSetNeedsDisplay = true
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("TerminalCanvas is created in code") }

    override func draw(_ dirtyRect: NSRect) {
        terminal?.drawFrame(in: self, synchronously: false)
    }

    /// The first frame, drawn and shown with the layer's own transaction:
    /// a new surface on screen before its first frame was a blank flash at
    /// each switch to the tab.
    func drawFirstFrame() {
        guard let metal = layer as? CAMetalLayer else { return }
        metal.presentsWithTransaction = true
        terminal?.drawFrame(in: self, synchronously: true)
        metal.presentsWithTransaction = false
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
}
