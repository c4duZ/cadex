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
    /// The button a press sent to the program, so its drags and release go
    /// there too (CADEX_MOUSE_BUTTON_*).
    var reportedButton: Int32?
    /// The link under the pointer while ⌘ is held (TerminalLinks.swift).
    var hoveredLink: TerminalSession.Link?
    var trackingArea: NSTrackingArea?
}

/// Mouse: scrolling, selecting text, and clicks for programs that track the
/// mouse (vim, htop, tmux). Shift always selects, as in other terminals.
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
        let location = convert(event.locationInWindow, from: nil)
        session.wheel(programEvent(location, CADEX_MOUSE_PRESS, CADEX_MOUSE_BUTTON_NONE, event), rows: rows)
        needsDisplay = true
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let location = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command), openLink(at: location) { return }
        if reportPress(event, button: CADEX_MOUSE_BUTTON_LEFT) { return }
        session?.selectPress(
            geometry.pointer(at: location),
            clicks: event.clickCount,
            extend: event.modifierFlags.contains(.shift))
        mouse.selecting = true
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        if reportMotion(event) { return }
        guard mouse.selecting, let session else { return }
        mouse.lastDragLocation = convert(event.locationInWindow, from: nil)
        let direction = session.selectDrag(geometry.pointer(at: mouse.lastDragLocation))
        updateAutoscroll(direction)
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        if reportRelease(event) { return }
        guard mouse.selecting else { return }
        mouse.selecting = false
        updateAutoscroll(0)
        let location = convert(event.locationInWindow, from: nil)
        session?.selectRelease(geometry.pointer(at: location))
        // Only when the setting is on; a click without a selection never
        // copies (docs/spec/terminal.md).
        if copyOnSelect, session?.hasSelection == true { copySelection() }
    }

    public override func rightMouseDown(with event: NSEvent) {
        if !reportPress(event, button: CADEX_MOUSE_BUTTON_RIGHT) { super.rightMouseDown(with: event) }
    }

    public override func rightMouseDragged(with event: NSEvent) { _ = reportMotion(event) }
    public override func rightMouseUp(with event: NSEvent) { _ = reportRelease(event) }

    public override func otherMouseDown(with event: NSEvent) {
        _ = reportPress(event, button: CADEX_MOUSE_BUTTON_MIDDLE)
    }

    public override func otherMouseDragged(with event: NSEvent) { _ = reportMotion(event) }
    public override func otherMouseUp(with event: NSEvent) { _ = reportRelease(event) }

    /// Motion without a button, for programs that track every motion.
    func reportHover(_ event: NSEvent) {
        guard let session, session.mouseTracking == UInt8(CADEX_MOUSE_TRACKING_MOTION) else { return }
        let location = convert(event.locationInWindow, from: nil)
        session.mouse(programEvent(location, CADEX_MOUSE_MOTION, CADEX_MOUSE_BUTTON_NONE, event))
    }

    // MARK: Reporting to the program

    /// Sends a press to the program if it tracks the mouse and Shift is not
    /// held. Returns false to let the click select locally.
    private func reportPress(_ event: NSEvent, button: Int32) -> Bool {
        guard let session, session.mouseTracking != UInt8(CADEX_MOUSE_TRACKING_NONE),
              !event.modifierFlags.contains(.shift)
        else { return false }
        let location = convert(event.locationInWindow, from: nil)
        session.mouse(programEvent(location, CADEX_MOUSE_PRESS, button, event))
        mouse.reportedButton = button
        return true
    }

    private func reportMotion(_ event: NSEvent) -> Bool {
        guard let session, let button = mouse.reportedButton else { return false }
        let location = convert(event.locationInWindow, from: nil)
        session.mouse(programEvent(location, CADEX_MOUSE_MOTION, button, event))
        return true
    }

    private func reportRelease(_ event: NSEvent) -> Bool {
        guard let session, let button = mouse.reportedButton else { return false }
        mouse.reportedButton = nil
        let location = convert(event.locationInWindow, from: nil)
        session.mouse(programEvent(location, CADEX_MOUSE_RELEASE, button, event))
        return true
    }

    private func programEvent(_ location: CGPoint, _ action: Int32, _ button: Int32, _ event: NSEvent) -> cadex_terminal_mouse_event {
        let mods = KeyEncoding.coreMods(event.modifierFlags, meta: event.modifierFlags.contains(.option))
        return geometry.mouseEvent(at: location, action: action, button: button, mods: mods)
    }

    // MARK: Autoscroll

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
