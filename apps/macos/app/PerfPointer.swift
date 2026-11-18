import AppKit

/// CADEX_PERF_HOVER: the pointer moved over the test instance without moving the owner's: mouse
/// moves posted to this process only (CGEvent.postToPid), so tracking areas and hover can be
/// checked in a capture (the owner, 2026-11-18: "passa o mouse e nada acende"). The value is
/// "panel|window:fx,fy;fx,fy…", fractions of the frontmost panel (the palette, a menu) or of the
/// window, y from the top; one point every 0.15 s from CADEX_PERF_HOVER_AT s.
extension WindowSession {
    func startPerfHover(_ spec: String, at: Double) {
        let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let points = parts[1].split(separator: ";").compactMap { pair -> CGPoint? in
            let xy = pair.split(separator: ",").compactMap { Double($0) }
            return xy.count == 2 ? CGPoint(x: xy[0], y: xy[1]) : nil
        }
        for (index, fraction) in points.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + at + Double(index) * 0.15) { [weak self] in
                guard let self, let target = parts[0] == "panel" ? Self.frontPanel(besides: self.window) : self.window else { return }
                Self.postMove(to: target, fraction: fraction)
            }
        }
    }

    /// CADEX_PERF_CLICK: clicks given to the window at "fx,fy;fx,fy…" of the window (y from
    /// the top), one every CADEX_PERF_CLICK_GAP s (1.5) from CADEX_PERF_CLICK_AT s: the real path of
    /// a click (the window's hit test, the view's mouseUp), without the owner's mouse.
    func startPerfClicks(_ spec: String, at: Double, gap: Double) {
        let points = spec.split(separator: ";").compactMap { pair -> CGPoint? in
            let xy = pair.split(separator: ",").compactMap { Double($0) }
            return xy.count == 2 ? CGPoint(x: xy[0], y: xy[1]) : nil
        }
        for (index, fraction) in points.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + at + Double(index) * gap) { [weak self] in
                guard let self else { return }
                let frame = self.window.frame
                let point = NSPoint(x: frame.minX + frame.width * fraction.x, y: frame.maxY - frame.height * fraction.y)
                // Built with the window and given to it: a click posted to the process came with no
                // window (logged 2026-11-18, windowNumber 0) and reached no view. From sendEvent on it is
                // a click's own path: the hit test, mouseDown, mouseUp.
                let local = self.window.convertPoint(fromScreen: point)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let event = NSEvent.mouseEvent(with: type, location: local, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: self.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                        self.window.sendEvent(event)
                    }
                }
                NSLog("perf click %.0f,%.0f", point.x, point.y)
            }
        }
    }

    private static func frontPanel(besides window: NSWindow) -> NSWindow? {
        NSApp.windows.filter { $0 !== window && $0.isVisible && $0 is NSPanel && $0.frame.width > 100 }.last
    }

    private static func postMove(to target: NSWindow, fraction: CGPoint) {
        let frame = target.frame
        let point = NSPoint(x: frame.minX + frame.width * fraction.x, y: frame.maxY - frame.height * fraction.y)
        // Quartz counts from the top of the main screen.
        let screenTop = NSScreen.screens.first?.frame.maxY ?? frame.maxY
        let quartz = CGPoint(x: point.x, y: screenTop - point.y)
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: quartz, mouseButton: .left) else { return }
        event.postToPid(getpid())
        NSLog("perf hover %@ %.0f,%.0f", target.className, point.x, point.y)
        // Tracking areas are the window server's: a posted move never reaches them. Delivered here
        // as it would: to the view under the point that tracks moves, and each one above it.
        guard target is NSPanel == false, let content = target.contentView?.superview ?? target.contentView,
              let local = NSEvent.mouseEvent(with: .mouseMoved, location: target.convertPoint(fromScreen: point), modifierFlags: [],
                                             timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: target.windowNumber,
                                             context: nil, eventNumber: 0, clickCount: 0, pressure: 0) else { return }
        var view = content.hitTest(content.convert(local.locationInWindow, from: nil))
        while let current = view {
            // The app's own views only: AppKit's (the window frame) ask a posted event for its area and throw.
            if !NSStringFromClass(type(of: current)).hasPrefix("NS"),
               current.trackingAreas.contains(where: { $0.owner === current && $0.options.contains(.mouseMoved) }) {
                current.mouseMoved(with: local)
            }
            view = current.superview
        }
    }
}
