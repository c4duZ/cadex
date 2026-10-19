import AppKit
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
        session?.onOutput = { [weak self] in self?.needsDisplay = true }
        session?.onExit = { [weak self] _ in self?.window?.close() }
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
        renderer.draw(frame.pointee, padding: SIMD2(padding, padding), in: drawable, size: drawableSize)
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
        if let bytes = KeyEncoding.sequence(keyCode: event.keyCode, modifiers: event.modifierFlags, characters: event.characters) {
            session?.write(bytes)
            return
        }
        // Text goes through the input system so dead keys compose.
        interpretKeyEvents([event])
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command), window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        // ⌘← ⌘→ ⌘⌫ ⌘⌦: line editing, sent to the shell.
        if let editing = KeyEncoding.sequence(keyCode: event.keyCode, modifiers: event.modifierFlags, characters: event.characters) {
            session?.write(editing)
            return true
        }
        switch event.charactersIgnoringModifiers {
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

    /// First version of ⌘V: text only. Files, images and bracketed paste
    /// follow docs/spec/terminal.md in the next step.
    private func paste() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        session?.write(text)
    }
}
