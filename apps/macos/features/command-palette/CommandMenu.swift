import AppKit

/// The app menu, generated from the registry: one submenu per category,
/// each item running its command by id. Items show the shortcut in effect
/// and grey out when the command is unavailable.
@MainActor
public final class CommandMenu: NSObject, NSMenuItemValidation {
    public typealias KeyEquivalent = (key: String, modifiers: NSEvent.ModifierFlags)

    private let registry: CommandRegistry
    private let keyEquivalent: (String) -> KeyEquivalent?

    /// keyEquivalent: the shortcut of a command id, from Shortcuts.
    public init(registry: CommandRegistry, keyEquivalent: @escaping (String) -> KeyEquivalent?) {
        self.registry = registry
        self.keyEquivalent = keyEquivalent
    }

    public func build() -> NSMenu {
        let main = NSMenu()
        for category in Command.Category.allCases {
            let commands = registry.commands.filter { $0.category == category }
            guard !commands.isEmpty else { continue }
            let submenu = NSMenu(title: category.title)
            commands.forEach { submenu.addItem(item(for: $0)) }
            let top = NSMenuItem(title: category.title, action: nil, keyEquivalent: "")
            top.submenu = submenu
            main.addItem(top)
        }
        return main
    }

    private func item(for command: Command) -> NSMenuItem {
        let item = NSMenuItem(title: command.title, action: #selector(runItem(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = command.id
        if let shortcut = keyEquivalent(command.id) {
            item.keyEquivalent = shortcut.key
            item.keyEquivalentModifierMask = shortcut.modifiers
        }
        return item
    }

    @objc private func runItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        registry.run(id)
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let id = menuItem.representedObject as? String else { return true }
        return registry.unavailableReason(id) == nil
    }
}
