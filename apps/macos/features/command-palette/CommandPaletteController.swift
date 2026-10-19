import AppKit

/// The palette over the key window: ⌘K lists commands; other features open
/// it with their own source (⌘P files, ⌘⇧F text). Registers palette.open.
@MainActor
public final class CommandPaletteController {
    private let registry: CommandRegistry
    private lazy var commands = CommandSource(registry: registry, shortcut: shortcut)
    private let shortcut: (String) -> String?
    private lazy var panel = makePanel()
    private var items: [PaletteItem] = []
    private var source: PaletteSource?
    /// Each query's results carry its number; late results of an older
    /// query are dropped.
    private var generation = 0
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

    /// The source on screen, if the palette is open.
    public var currentSource: PaletteSource? { panel.isVisible ? source : nil }

    public func toggle() {
        open(commands)
    }

    /// Shows `source`. Pressing the same shortcut again closes the palette;
    /// another one switches to its source, keeping nothing of the old one.
    public func open(_ newSource: PaletteSource) {
        if panel.isVisible, source === newSource {
            dismiss()
            return
        }
        source?.stop()
        source = newSource
        if !panel.isVisible {
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
            parent = window
            panel.show(over: window)
        }
        panel.prepare(placeholder: newSource.placeholder, emptyText: newSource.emptyText)
    }

    /// Runs the current text again (an option of the source changed).
    public func refresh() {
        guard panel.isVisible else { return }
        search(panel.query)
    }

    private func makePanel() -> CommandPalettePanel {
        let panel = CommandPalettePanel()
        panel.onQuery = { [weak self] query in self?.search(query) }
        panel.onChoose = { [weak self] row in self?.choose(row) }
        panel.onDismiss = { [weak self] in self?.dismiss() }
        return panel
    }

    private func search(_ query: String) {
        generation += 1
        let current = generation
        source?.search(query) { [weak self] items, status in
            guard let self, current == self.generation else { return }
            self.items = items
            self.panel.show(items: items, status: status)
        }
    }

    /// Closes first and gives the focus back, so a command that acts on
    /// the focused view (copy, clear) finds the terminal, not the palette.
    private func choose(_ row: Int) {
        let item = items[row]
        let chosen = source
        dismiss()
        chosen?.choose(item)
    }

    private func dismiss() {
        source?.stop()
        generation += 1
        panel.orderOut(nil)
        parent?.makeKeyAndOrderFront(nil)
    }
}
