import AppKit

/// The app's window. In full screen AppKit leaves it on an Escape that nobody took
/// (NSWindow.cancelOperation, like the green button), and in Cadex the Esc that reaches the
/// window is never the owner asking that: the preview's page passes back the keys it does not use,
/// so the owner's Esc there and the agent's (browser_press Escape, 8 times on 2026-11-23) took the
/// window out of full screen; the sidebar sends its own up the chain too. The owner leaves full
/// screen by the green button or ⌃⌘F (the owner, 2026-11-23: "tirava o cadex da tela cheia,
/// como se clicasse no ícone verde").
final class CadexWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        if styleMask.contains(.fullScreen) { return }
        super.cancelOperation(sender)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, styleMask.contains(.fullScreen) { return }
        super.keyDown(with: event)
    }
}
