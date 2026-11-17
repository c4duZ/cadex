import AppKit
import CommandPalette

/// Runs commands from key presses before any view sees them, which is what
/// lets ⌘K open the palette even with the terminal focused (ADR 0005).
/// A press whose command is unavailable goes on to the view as usual.
@MainActor
public final class ShortcutDispatcher {
    /// The key window's commands: each window has its own (⌘N), and the
    /// app swaps this when another window comes to the front.
    public var registry: CommandRegistry
    private var keymap: Keymap
    private var monitor: Any?
    /// While true, presses go to the views untouched (the settings window
    /// recording a new shortcut).
    public var isSuspended = false
    /// A press another part takes first (⌘1…⌘9 in ⌘J's list, which are tab.select-1…9 elsewhere):
    /// true when it took it, and then nothing else does, not the command and not the menu (with
    /// no key window the menu came first and switched the tab, 2026-11-17).
    public var takenFirst: ((NSEvent) -> Bool)?

    public init(registry: CommandRegistry, keymap: Keymap) {
        self.registry = registry
        self.keymap = keymap
    }

    /// Settings changed the shortcuts: new presses use the new map.
    public func update(keymap: Keymap) {
        self.keymap = keymap
    }

    public func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Local monitors run on the main thread; NSEvent is not Sendable,
            // so it crosses into the main-actor call unchecked.
            nonisolated(unsafe) let pressed = event
            let handled = MainActor.assumeIsolated { self?.handle(pressed) ?? false }
            return handled ? nil : event
        }
    }

    public func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// True when the press ran a command and must not reach the view.
    public func handle(_ event: NSEvent) -> Bool {
        if takenFirst?(event) == true { return true }
        guard !isSuspended, let combo = KeyCombo(event: event), let id = keymap.command(for: combo) else { return false }
        return registry.run(id)
    }
}
