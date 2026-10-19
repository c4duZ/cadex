import AppKit

/// ⌘K: shows the palette over the key window and runs what the user picks.
/// Registers the palette.open command itself.
@MainActor
public final class CommandPaletteController {
    private let registry: CommandRegistry
    private let shortcut: (String) -> String?
    private lazy var panel = makePanel()
    private var items: [PaletteItem] = []
    /// The window the palette opened over; it gets the focus back.
    private weak var parent: NSWindow?

    /// shortcut: the label of a command's shortcut ("⌘T"), from Shortcuts.
    public init(registry: CommandRegistry, shortcut: @escaping (String) -> String?) {
        self.registry = registry
        self.shortcut = shortcut
    }

    /// The command that opens the palette, and closes it when open.
    public var openCommand: Command {
        Command(id: "palette.open", title: "Abrir a paleta de comandos", keywords: ["comandos", "command palette"],
                category: .app, defaultShortcut: "cmd+k", action: .run { [weak self] in self?.toggle() })
    }

    public var isOpen: Bool { panel.isVisible }

    public func toggle() {
        if panel.isVisible {
            dismiss()
            return
        }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        parent = window
        panel.show(over: window)
    }

    private func makePanel() -> CommandPalettePanel {
        let panel = CommandPalettePanel()
        panel.onQuery = { [weak self] query in self?.search(query) }
        panel.onChoose = { [weak self] row in self?.choose(row) }
        panel.onDismiss = { [weak self] in self?.dismiss() }
        return panel
    }

    private func search(_ query: String) {
        items = PaletteModel.items(for: query, registry: registry, shortcut: shortcut)
        panel.show(items: items)
    }

    /// Closes first and gives the focus back, so a command that acts on
    /// the focused view (copy, clear) finds the terminal, not the palette.
    private func choose(_ row: Int) {
        let id = items[row].id
        dismiss()
        registry.run(id)
    }

    private func dismiss() {
        panel.orderOut(nil)
        parent?.makeKeyAndOrderFront(nil)
    }
}
