import CommandPalette
import Foundation

/// Which command each key combination runs: the defaults declared by the
/// commands, then the user's preferences file on top (docs/spec/shortcuts.md).
@MainActor
public struct Keymap {
    public private(set) var bindings: [KeyCombo: String] = [:]
    /// What loading found wrong, for the log: unknown ids, refused Ctrl
    /// keys, defaults a custom shortcut took over, a broken file.
    public private(set) var problems: [String] = []

    /// The defaults of every registered command.
    public init(registry: CommandRegistry) {
        for command in registry.commands {
            guard let text = command.defaultShortcut else { continue }
            guard let combo = KeyCombo(text) else {
                problems.append("atalho padrão inválido em \(command.id): \(text)")
                continue
            }
            if let other = bindings[combo] {
                problems.append("atalho padrão \(text) repetido em \(other) e \(command.id)")
            }
            bindings[combo] = command.id
        }
    }

    /// The user's shortcuts from settings.json: combination → command id, or
    /// nil to turn a default off.
    public mutating func applyPreferences(_ shortcuts: [String: String?], registry: CommandRegistry) {
        applyPreferences(shortcuts.mapValues { $0.map { $0 as Any } ?? NSNull() }, registry: registry)
    }

    public mutating func applyPreferences(_ map: [String: Any], registry: CommandRegistry) {
        for (text, value) in map.sorted(by: { $0.key < $1.key }) {
            guard let combo = KeyCombo(text) else {
                problems.append("atalho inválido: \(text)")
                continue
            }
            if value is NSNull {
                bindings[combo] = nil
                continue
            }
            guard let id = value as? String, registry.command(id) != nil else {
                problems.append("\(text) aponta para um comando que não existe: \(value)")
                continue
            }
            guard !combo.isTerminalControlKey else {
                problems.append("\(text) recusado: Ctrl+tecla é dos programas no terminal")
                continue
            }
            if let replaced = bindings[combo], replaced != id {
                problems.append("\(text) agora roda \(id) no lugar de \(replaced)")
            }
            bindings[combo] = id
        }
    }

    public func command(for combo: KeyCombo) -> String? {
        bindings[combo]
    }

    /// The combination shown next to a command: the first one, in a stable
    /// order, when several run it.
    public func combo(for id: String) -> KeyCombo? {
        bindings.filter { $0.value == id }.keys.min { $0.description < $1.description }
    }
}
