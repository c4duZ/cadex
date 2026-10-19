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
    /// typing ∫. Off by default (docs/spec/terminal.md, Teclado); the settings
    /// window (plan 3) will write this default.
    public var optionAsMeta = UserDefaults.standard.bool(forKey: "terminal.optionAsMeta")
    /// Copy on select (docs/spec/terminal.md): off by default, so hovering,
    /// clicking or selecting never replaces what is on the clipboard.
    public var copyOnSelect = UserDefaults.standard.bool(forKey: "terminal.copyOnSelect")
    /// Scroll and drag state (TerminalMouse.swift).
    var mouse = MouseState()
    /// Created on the first ⌘F (TerminalFind.swift).
    var findBar: TerminalFindBar?

    public init(frame: CGRect, cwd: String? = nil) {
        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        // Draw on demand: only when the shell sends output or the view changes.
        isPaused = true
        enableSetNeedsDisplay = true

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        if let device {
            renderer = TerminalRenderer(device: device, font: TerminalFont(scale: scale), pixelFormat: colorPixelFormat)
        }
        let size = gridSize()
        session = try? TerminalSession(cols: size.cols, rows: size.rows, cwd: cwd)
        session?.onOutput = { [weak self] in
            self?.needsDisplay = true
            self?.refreshFindCounts()
        }
        session?.onExit = { [weak self] _ in self?.window?.close() }
        registerForDraggedTypes([.fileURL])
        Self.cleanPastedImagesOnce()
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
        renderer.draw(frame.pointee, padding: SIMD2(padding, padding), in: drawable, size: drawableSize,
                      linkCells: hoveredLinkCells)
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        resizeSession()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // Moved to a screen with another scale: rasterize glyphs for it, or
        // they are scaled and blurry.
        renderer?.setFont(TerminalFont(scale: scale))
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

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘F also works while typing in the find bar (it selects the text).
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "f",
           let bar = findBar, !bar.isHidden {
            showFindBar()
            return true
        }
        guard event.modifierFlags.contains(.command), window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        // ⌘← ⌘→ ⌘⌫ ⌘⌦: line editing, sent to the shell.
        if case .macEditing(let editing) = KeyEncoding.route(keyCode: event.keyCode, modifiers: event.modifierFlags, optionAsMeta: optionAsMeta) {
            session?.write(editing)
            return true
        }
        if let jump = Self.historyJumps[event.keyCode] {
            jump == .top ? session?.scrollToTop() : session?.scrollToBottom()
            needsDisplay = true
            return true
        }
        switch event.charactersIgnoringModifiers {
        case "c":
            copySelection()
            return true
        case "f":
            showFindBar()
            return true
        case "a":
            session?.selectAll()
            needsDisplay = true
            return true
        case "v":
            paste()
            return true
        case "l":
            // Clear screen (docs/spec/terminal.md): Ctrl+L, which shells redraw.
            session?.write("\u{0C}")
            return true
        case "k":
            // Reserved for the command palette (ADR 0005); never reaches the shell.
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    private enum HistoryJump { case top, bottom }
    /// ⌘↑ and ⌘↓ (key codes 126 and 125): top and bottom of the history.
    private static let historyJumps: [UInt16: HistoryJump] = [126: .top, 125: .bottom]

    /// ⌘C: only the selection, and only when there is one; without it the
    /// clipboard keeps what it had (docs/spec/terminal.md).
    func copySelection() {
        guard let text = session?.selectedText() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
