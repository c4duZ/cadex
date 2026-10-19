import AppKit
import CommandPalette

/// Runs commands from key presses before any view sees them, which is what
/// lets ⌘K open the palette even with the terminal focused (ADR 0005).
/// A press whose command is unavailable goes on to the view as usual.
@MainActor
public final class ShortcutDispatcher {
    private let registry: CommandRegistry
    private var keymap: Keymap
    private var monitor: Any?

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
        guard let combo = KeyCombo(event: event), let id = keymap.command(for: combo) else { return false }
        return registry.run(id)
    }
}
