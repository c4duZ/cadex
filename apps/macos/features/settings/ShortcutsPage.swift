import AppKit
import CommandPalette
import Shortcuts

/// The "Atalhos" page: every command with its shortcut. Clicking a shortcut
/// records the next key combination; Delete clears it, Esc cancels. A
/// combination another command had moves here, and the message says so
/// (docs/spec/shortcuts.md, conflito).
@MainActor
final class ShortcutsPage {
    private let store: SettingsStore
    private let registry: CommandRegistry
    private let keymap: () -> Keymap
    /// Stops the app's shortcuts while recording, or ⌘T would open a tab.
    private let suspendShortcuts: (Bool) -> Void
    private var buttons: [String: NSButton] = [:]
    private var resets: [String: NSButton] = [:]
    private let message = NSTextField(labelWithString: "")
    private var recording: (id: String, monitor: Any)?

    init(store: SettingsStore, registry: CommandRegistry, keymap: @escaping () -> Keymap,
         suspendShortcuts: @escaping (Bool) -> Void) {
        self.store = store
        self.registry = registry
        self.keymap = keymap
        self.suspendShortcuts = suspendShortcuts
    }

    func makeView() -> NSView {
        message.textColor = SettingsColors.secondaryText
        var rows: [NSView] = [message]
        for category in Command.Category.allCases {
            let commands = registry.commands.filter { $0.category == category }
            guard !commands.isEmpty else { continue }
            rows.append(SettingsPage.section(category.title))
            rows += commands.map(row)
        }
        refreshLabels()
        return SettingsPage.make(title: "Atalhos", subtitle: "Clique num atalho e aperte as teclas novas.", rows: rows)
    }

    private func row(_ command: Command) -> NSView {
        let button = NSButton(title: "", target: nil, action: nil)
        button.bezelStyle = .rounded
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        button.target = ActionBox.keep(button) { [weak self] in self?.record(command.id) }
        button.action = #selector(ActionBox.fire)
        buttons[command.id] = button
        let reset = NSButton(title: "Padrão", target: nil, action: nil)
        reset.bezelStyle = .inline
        reset.target = ActionBox.keep(reset) { [weak self] in self?.restoreDefault(command) }
        reset.action = #selector(ActionBox.fire)
        reset.toolTip = "Voltar ao atalho padrão"
        resets[command.id] = reset
        let controls = NSStackView(views: [reset, button])
        controls.spacing = 6
        return SettingsPage.row(command.title, nil, control: controls)
    }

    private func refreshLabels() {
        let map = keymap()
        for (id, button) in buttons where recording?.id != id {
            button.title = map.combo(for: id)?.label ?? "—"
        }
        // "Padrão" only where the user changed something for this command.
        let custom = store.settings.shortcuts
        for (id, reset) in resets {
            let defaultText = registry.command(id)?.defaultShortcut.flatMap(KeyCombo.init)?.description
            reset.isHidden = !custom.contains { combo, target in target == id || (target == nil && combo == defaultText) }
        }
    }

    private func record(_ id: String) {
        stopRecording()
        buttons[id]?.title = "Aperte as teclas…"
        suspendShortcuts(true)
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            nonisolated(unsafe) let pressed = event
            MainActor.assumeIsolated { self?.capture(pressed, for: id) }
            return nil
        }
        recording = (id, monitor as Any)
    }

    private func capture(_ event: NSEvent, for id: String) {
        defer { stopRecording(); refreshLabels() }
        if event.keyCode == 53 { return }  // Esc: cancel.
        if event.keyCode == 51 {           // Delete: no shortcut.
            store.update { settings in
                for (combo, target) in keymap().bindings where target == id { settings.shortcuts[combo.description] = .some(nil) }
            }
            message.stringValue = "Atalho removido."
            return
        }
        guard let combo = KeyCombo(event: event) else { return }
        guard !combo.isTerminalControlKey else {
            message.stringValue = "\(combo.label) é dos programas no terminal; escolha outra combinação."
            return
        }
        let previous = keymap().command(for: combo)
        store.update { settings in
            for (old, target) in keymap().bindings where target == id && old != combo {
                settings.shortcuts[old.description] = .some(nil)
            }
            settings.shortcuts[combo.description] = .some(id)
        }
        if let previous, previous != id {
            message.stringValue = "\(combo.label) era de \"\(registry.command(previous)?.title ?? previous)\" e agora é deste comando."
        } else {
            message.stringValue = ""
        }
    }

    private func restoreDefault(_ command: Command) {
        store.update { settings in
            settings.shortcuts = settings.shortcuts.filter { _, target in target != command.id }
            if let text = command.defaultShortcut, let combo = KeyCombo(text) {
                settings.shortcuts[combo.description] = nil
            }
        }
        message.stringValue = ""
        refreshLabels()
    }

    private func stopRecording() {
        if let monitor = recording?.monitor { NSEvent.removeMonitor(monitor) }
        if recording != nil { suspendShortcuts(false) }
        recording = nil
    }
}
