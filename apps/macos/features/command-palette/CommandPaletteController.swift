import AppKit
import Icons

/// The palette over the key window: ⌘K lists commands; other features open
/// it with their own source (⌘P files, ⌘⇧F text). Registers palette.open.
@MainActor
public final class CommandPaletteController {
    private let registry: CommandRegistry
    lazy var commands = CommandSource(registry: registry, shortcut: shortcut)
    private let shortcut: (String) -> String?
    private lazy var panel = makePanel()
    private var items: [PaletteItem] = []
    private var source: PaletteSource?
    /// Each query's results carry its number; late results of an older
    /// query are dropped.
    private var generation = 0
    /// The window the palette opened over; it gets the focus back.
    private weak var parent: NSWindow?
    /// Lists reached from ⌘K by the first character: "/" files, "#" text,
    /// "@" tabs and spaces (docs/spec/command-palette.md). ">" is commands.
    private var prefixes: [(prefix: Character, label: String, source: PaletteSource)] = []
    /// The list answering now: the source, or the one its prefix picked.
    private var answering: PaletteSource?

    /// The theme's colors, from the app.
    public var style: PaletteStyle {
        get { panel.style }
        set { panel.style = newValue }
    }

    /// The commands ⌘K shows first, under "Abrir".
    public var pins: [PalettePin] {
        get { commands.pins }
        set { commands.pins = newValue }
    }

    /// Typing `prefix` first in ⌘K lists `source` with the rest of the text.
    public func addPrefix(_ prefix: Character, label: String, source: PaletteSource) {
        prefixes.append((prefix, label, source))
    }

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
        answering?.stop()
        answering = nil
        source = newSource
        if !panel.isVisible {
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
            parent = window
            panel.show(over: window)
        }
        panel.prepare(placeholder: newSource.placeholder, emptyText: newSource.emptyText, icon: newSource.icon)
    }

    /// Runs the current text again (an option of the source changed).
    public func refresh() {
        guard panel.isVisible else { return }
        search(panel.query)
    }

    private func makePanel() -> CommandPalettePanel {
        let panel = CommandPalettePanel()
        panel.onQuery = { [weak self] query in self?.search(query) }
        panel.onChoose = { [weak self] row, choice in self?.choose(row, as: choice) }
        panel.onDismiss = { [weak self] in self?.dismiss() }
        return panel
    }

    private func search(_ query: String) {
        generation += 1
        let current = generation
        let (list, text) = route(query, from: source)
        if list !== answering {
            answering?.stop()
            answering = list
            if let list { panel.setLook(placeholder: list.placeholder, emptyText: list.emptyText, icon: list.icon) }
        }
        let hints = footer(for: list, empty: query.isEmpty)
        list?.search(text) { [weak self] items, status in
            guard let self, current == self.generation else { return }
            self.items = items
            self.panel.show(items: items, status: status, hints: hints)
        }
    }

    /// Which list answers `query`: in ⌘K, a prefix picks another one and
    /// the rest of the text goes to it; ">" stays on the commands.
    func route(_ query: String, from source: PaletteSource?) -> (PaletteSource?, String) {
        guard source === commands, let first = query.first else { return (source, query) }
        if first == ">" { return (commands, String(query.dropFirst()).trimmingCharacters(in: .whitespaces)) }
        guard let match = prefixes.first(where: { $0.prefix == first }) else { return (source, query) }
        return (match.source, String(query.dropFirst()).trimmingCharacters(in: .whitespaces))
    }

    /// The list's keys, then moving and closing; with ⌘K empty, the prefixes.
    private func footer(for list: PaletteSource?, empty: Bool) -> [PaletteHint] {
        let own = list?.hints ?? []
        if empty, list === commands, !prefixes.isEmpty {
            return own + [PaletteHint(">", "comandos")] + prefixes.map { PaletteHint(String($0.prefix), $0.label) }
        }
        return own + [PaletteHint("↑↓", "mover"), PaletteHint("esc", "fechar")]
    }

    /// Closes first and gives the focus back, so a command that acts on
    /// the focused view (copy, clear) finds the terminal, not the palette.
    private func choose(_ row: Int, as choice: PaletteChoice) {
        let item = items[row]
        let chosen = answering
        dismiss()
        choice == .primary ? chosen?.choose(item) : chosen?.choose(item, as: choice)
    }

    private func dismiss() {
        source?.stop()
        answering?.stop()
        answering = nil
        generation += 1
        panel.orderOut(nil)
        parent?.makeKeyAndOrderFront(nil)
    }
}
