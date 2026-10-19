import AppKit
import CCadex
import MetalKit

/// The terminal on screen: draws the session with Metal, sends keys and
/// pasted text to it, and resizes it with the view.
@MainActor
public final class TerminalView: MTKView {
    /// Space between the window edge and the text, in points.
    private static let paddingPoints: CGFloat = 8

    public private(set) var session: TerminalSession?
    private var renderer: TerminalRenderer?
    private var lastSize: (cols: UInt16, rows: UInt16) = (0, 0)
    var markedText = NSAttributedString()
    /// Left Option as Meta (Option+B goes to the shell as Meta+B) instead of
    /// typing ∫. Off by default (docs/spec/terminal.md, Teclado).
    var optionAsMeta: Bool { TerminalPreferences.current.optionAsMeta }
    /// Copy on select (docs/spec/terminal.md): off by default, so hovering,
    /// clicking or selecting never replaces what is on the clipboard.
    var copyOnSelect: Bool { TerminalPreferences.current.copyOnSelect }
    /// Scroll and drag state (TerminalMouse.swift).
    var mouse = MouseState()
    /// Created on the first ⌘F (TerminalFind.swift).
    var findBar: TerminalFindBar?
    /// Bell flash and cursor blink (TerminalSignals.swift).
    var signals = SignalState()

    /// The shell exited. Whoever holds the view (a tab, a pane) closes it;
    /// without a handler the window closes.
    public var onShellExit: (() -> Void)?
    /// New output arrived; tabs refresh the folder in their title.
    public var onActivity: (() -> Void)?
    /// The program set the title (OSC 0/2); without a handler it goes to
    /// the window.
    public var onProgramTitle: ((String) -> Void)?
    /// The view took the keyboard focus (a click on a pane, for example).
    public var onFocus: (() -> Void)?
    /// "Abrir no preview" was clicked for a local server's address (the
    /// offer shows only when this is set).
    public var onOpenPreview: ((String) -> Void)?
    var previewOffer: TerminalPreviewOffer?

    public init(frame: CGRect, cwd: String? = nil) {
        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        // Draw on demand: only when the shell sends output or the view changes.
        isPaused = true
        enableSetNeedsDisplay = true

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        if let device {
            renderer = TerminalRenderer(device: device, font: Self.preferredFont(scale: scale), pixelFormat: colorPixelFormat)
        }
        let size = gridSize()
        let preferences = TerminalPreferences.current
        session = try? TerminalSession(cols: size.cols, rows: size.rows, cwd: cwd,
                                       shell: preferences.shell.isEmpty ? nil : preferences.shell,
                                       historyLines: UInt32(clamping: preferences.historyLines))
        session?.onOutput = { [weak self] in
            self?.needsDisplay = true
            self?.refreshFindCounts()
            self?.onActivity?()
        }
        session?.onExit = { [weak self] _ in
            guard let self else { return }
            if let handler = self.onShellExit { handler() } else { self.window?.close() }
        }
        session?.onLocalURL = { [weak self] url in self?.offerPreview(url) }
        connectSignals()
        followAppearance()
        followPreferences()
        registerForDraggedTypes([.fileURL])
        Self.cleanPastedImagesOnce()
    }

    static func preferredFont(scale: CGFloat) -> TerminalFont {
        let preferences = TerminalPreferences.current
        return TerminalFont(family: preferences.fontFamily, pointSize: preferences.fontSize, scale: scale)
    }

    /// Font and cursor follow the preferences live; the rest is read when
    /// needed (TerminalPreferences.swift).
    private func followPreferences() {
        applyCursorPreference()
        NotificationCenter.default.addObserver(forName: TerminalPreferences.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.applyCursorPreference()
                self.renderer?.setFont(Self.preferredFont(scale: self.scale))
                self.lastSize = (0, 0)
                self.resizeSession()
                self.needsDisplay = true
            }
        }
    }

    private func applyCursorPreference() {
        let preferences = TerminalPreferences.current
        session?.setCursor(shape: preferences.cursorShape.rawValue, blink: preferences.cursorBlink)
    }

    /// Takes the current theme colors now and whenever they change.
    private func followAppearance() {
        applyAppearance()
        NotificationCenter.default.addObserver(forName: TerminalAppearance.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAppearance() }
        }
    }

    private func applyAppearance() {
        guard let appearance = TerminalAppearance.current else { return }
        session?.setColors(appearance)
        renderer?.selectionColor = appearance.selection
        renderer?.backgroundAlpha = appearance.backgroundAlpha
        // Opaque unless a background image shows through: an opaque layer
        // costs less to composite.
        layer?.isOpaque = appearance.backgroundAlpha >= 1
        needsDisplay = true
    }

    /// Pasted images older than a week go away once per app launch.
    private static var cleanedPastedImages = false
    private static func cleanPastedImagesOnce() {
        guard !cleanedPastedImages else { return }
        cleanedPastedImages = true
        DispatchQueue.global(qos: .utility).async { PastedImageStore.removeOld() }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("TerminalView is created in code") }

    public override var acceptsFirstResponder: Bool { true }

    // MARK: Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let renderer, let session, let drawable = currentDrawable,
              let frame = session.currentFrame()
        else { return }
        let padding = Float(Self.paddingPoints * scale)
        updateBlink(programWantsBlink: frame.pointee.cursor_blinking)
        let overlay = DrawOverlay(linkCells: hoveredLinkCells, hideCursor: !signals.cursorShown, flash: isFlashing)
        renderer.draw(frame.pointee, padding: SIMD2(padding, padding), in: drawable, size: drawableSize, overlay: overlay)
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        resizeSession()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // Moved to a screen with another scale: rasterize glyphs for it, or
        // they are scaled and blurry.
        renderer?.setFont(Self.preferredFont(scale: scale))
        resizeSession()
    }

    private var scale: CGFloat { window?.backingScaleFactor ?? 2 }

    /// Points to cells for the current size, font and screen.
    var geometry: TerminalGeometry {
        let m = renderer?.metrics
        return TerminalGeometry(
            viewSize: bounds.size, scale: scale, padding: Self.paddingPoints,
            cellWidth: m.map { Int($0.width) } ?? 1, cellHeight: m.map { Int($0.height) } ?? 1,
            cols: Int(lastSize.cols), rows: Int(lastSize.rows))
    }

    private func gridSize() -> (cols: UInt16, rows: UInt16) {
        guard let m = renderer?.metrics else { return (80, 24) }
        let pad = Self.paddingPoints * 2 * scale
        let cols = Int((bounds.width * scale - pad) / CGFloat(m.width))
        let rows = Int((bounds.height * scale - pad) / CGFloat(m.height))
        return (UInt16(clamping: max(cols, 1)), UInt16(clamping: max(rows, 1)))
    }

    private func resizeSession() {
        guard let session, let m = renderer?.metrics else { return }
        let size = gridSize()
        if size == lastSize { return }
        lastSize = size
        session.resize(cols: size.cols, rows: size.rows, cellWidth: UInt16(m.width), cellHeight: UInt16(m.height))
        needsDisplay = true
    }

    // MARK: Keyboard

    public override func keyDown(with event: NSEvent) {
        restartBlink()
        // A dead key is waiting (´ before e): the input system decides what
        // Backspace, Escape or the next letter do with it.
        if hasMarkedText() {
            interpretKeyEvents([event])
            return
        }
        switch KeyEncoding.route(keyCode: event.keyCode, modifiers: event.modifierFlags, optionAsMeta: optionAsMeta) {
        case .macEditing(let bytes):
            session?.write(bytes)
        case .core(let key, let mods):
            sendToCore(event, key: key, mods: mods)
        case .text:
            // ⌘ with a key no command took (⌘J): not text for the shell.
            if event.modifierFlags.contains(.command) { return }
            interpretKeyEvents([event])
        }
    }

    /// The core needs the text without Ctrl and Option applied (Ctrl+C is
    /// "c", Meta+B is "b") and the key without Shift, for the kitty protocol.
    private func sendToCore(_ event: NSEvent, key: UInt16, mods: UInt8) {
        let isText = key == UInt16(CADEX_KEY_NONE)
        let text = isText ? event.characters(byApplyingModifiers: event.modifierFlags.intersection([.shift, .capsLock])) ?? "" : ""
        let unshifted = isText ? event.characters(byApplyingModifiers: [])?.unicodeScalars.first?.value ?? 0 : 0
        session?.key(key, mods: mods, text: text, unshifted: unshifted)
    }

    /// Only Mac-style line editing (⌘← ⌘→ ⌘⌫ ⌘⌦) is handled here: it is input
    /// for the shell, not an app action. Every other ⌘ shortcut is a command
    /// (ADR 0005), run by the Shortcuts dispatcher before this view sees it.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command), window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        if case .macEditing(let editing) = KeyEncoding.route(keyCode: event.keyCode, modifiers: event.modifierFlags, optionAsMeta: optionAsMeta) {
            session?.write(editing)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// ⌘C: only the selection, and only when there is one; without it the
    /// clipboard keeps what it had (docs/spec/terminal.md).
    func copySelection() {
        guard let text = session?.selectedText() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
