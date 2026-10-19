import AppKit

/// What the view tracks for signals from and to the program: the bell
/// flash and the blinking cursor.
struct SignalState {
    var flashUntil: Date?
    var blinkTimer: Timer?
    /// Off during the hidden half of a blink.
    var cursorShown = true
}

/// Signals between the view and the program: focus in and out (for
/// programs that asked), the window title (OSC 0/2), the bell (a short
/// flash, no sound) and the cursor blinking when the program asks for it.
extension TerminalView {
    /// Blink half-period, close to Terminal.app's.
    private static let blinkInterval: TimeInterval = 0.6
    /// How long the bell flash lasts.
    private static let bellFlash: TimeInterval = 0.15

    func connectSignals() {
        session?.onTitle = { [weak self] in self?.titleChanged() }
        session?.onBell = { [weak self] in self?.bellRang() }
    }

    // MARK: Focus

    public override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            focusChanged()
            onFocus?()
        }
        return accepted
    }

    public override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { session?.focus(false) }
        return accepted
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NotificationCenter.default
        center.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        center.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        guard let window else { return }
        // Output that came while the view had no window had nothing to draw
        // into: a space's first terminal stayed blank until the shell wrote
        // again (2026-10-19).
        needsDisplay = true
        center.addObserver(self, selector: #selector(windowKeyChanged), name: NSWindow.didBecomeKeyNotification, object: window)
        center.addObserver(self, selector: #selector(windowKeyChanged), name: NSWindow.didResignKeyNotification, object: window)
    }

    @objc private func windowKeyChanged() {
        guard window?.firstResponder === self else { return }
        focusChanged()
    }

    private func focusChanged() {
        session?.focus(window?.isKeyWindow == true && window?.firstResponder === self)
        needsDisplay = true
    }

    // MARK: Title and bell

    private func titleChanged() {
        let title = session?.title() ?? ""
        if let handler = onProgramTitle {
            handler(title)
        } else {
            window?.title = title.isEmpty ? "Cadex" : title
        }
    }

    /// The title the program set (OSC 0/2), empty if none.
    public var programTitle: String { session?.title() ?? "" }

    private func bellRang() {
        signals.flashUntil = Date().addingTimeInterval(Self.bellFlash)
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.bellFlash) { [weak self] in
            self?.needsDisplay = true
        }
        if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
    }

    var isFlashing: Bool {
        guard let until = signals.flashUntil else { return false }
        return Date() < until
    }

    // MARK: Cursor blink

    /// Called on every draw: blinks only while the program asks for it and
    /// the window is in front, so an idle terminal draws nothing.
    func updateBlink(programWantsBlink: Bool) {
        let blink = programWantsBlink && window?.isKeyWindow == true
        if !blink {
            signals.blinkTimer?.invalidate()
            signals.blinkTimer = nil
            signals.cursorShown = true
            return
        }
        guard signals.blinkTimer == nil else { return }
        signals.blinkTimer = Timer.scheduledTimer(withTimeInterval: Self.blinkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.signals.cursorShown.toggle()
                self.needsDisplay = true
            }
        }
    }

    /// Typing shows the cursor right away and restarts the blink.
    func restartBlink() {
        signals.blinkTimer?.invalidate()
        signals.blinkTimer = nil
        signals.cursorShown = true
    }
}
