import AppKit
import CCadex

/// What the view remembers between mouse events.
struct MouseState {
    var scroll = ScrollAccumulator()
    /// Runs while a drag is past the top or bottom edge (selection.zig).
    var autoscrollTimer: Timer?
    var lastDragLocation: CGPoint = .zero
    /// Set by mouseDown; mouseUp copies only after a press made a selection.
    var selecting = false
}

/// Mouse: scrolling the history and selecting text. The core keeps the
/// selection; this file converts positions and runs the autoscroll timer.
extension TerminalView {
    /// libghostty-vt's suggested pace for autoscroll: one row every ~15 ms.
    private static let autoscrollInterval: TimeInterval = 0.015

    public override func scrollWheel(with event: NSEvent) {
        guard let session else { return }
        if event.phase == .began { mouse.scroll.reset() }
        let g = geometry
        let rows = mouse.scroll.rows(
            deltaY: event.scrollingDeltaY,
            precise: event.hasPreciseScrollingDeltas,
            cellHeightPoints: CGFloat(g.cellHeight) / g.scale)
        guard rows != 0 else { return }
        session.scroll(rows: rows)
        needsDisplay = true
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        session?.selectPress(
            geometry.pointer(at: location),
            clicks: event.clickCount,
            extend: event.modifierFlags.contains(.shift))
        mouse.selecting = true
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        guard mouse.selecting, let session else { return }
        mouse.lastDragLocation = convert(event.locationInWindow, from: nil)
        let direction = session.selectDrag(geometry.pointer(at: mouse.lastDragLocation))
        updateAutoscroll(direction)
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        guard mouse.selecting else { return }
        mouse.selecting = false
        updateAutoscroll(0)
        let location = convert(event.locationInWindow, from: nil)
        session?.selectRelease(geometry.pointer(at: location))
        // Only when the setting is on; a click without a selection never
        // copies (docs/spec/terminal.md).
        if copyOnSelect, session?.hasSelection == true { copySelection() }
    }

    private func updateAutoscroll(_ direction: Int8) {
        if direction == 0 {
            mouse.autoscrollTimer?.invalidate()
            mouse.autoscrollTimer = nil
            return
        }
        guard mouse.autoscrollTimer == nil else { return }
        mouse.autoscrollTimer = Timer.scheduledTimer(withTimeInterval: Self.autoscrollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoscrollStep() }
        }
    }

    private func autoscrollStep() {
        guard mouse.selecting, let session else {
            updateAutoscroll(0)
            return
        }
        let direction = session.selectAutoscroll(geometry.pointer(at: mouse.lastDragLocation))
        needsDisplay = true
        if direction == 0 { updateAutoscroll(0) }
    }
}
