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

    /// The file of custom shortcuts: Application Support/Cadex/shortcuts.json.
    public static var preferencesFile: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Cadex/shortcuts.json")
    }

    /// Applies {"cmd+shift+t": "tab.new", "cmd+k": null} on top of the
    /// defaults. A missing file is fine; a broken one leaves the defaults.
    public mutating func applyPreferences(from url: URL, registry: CommandRegistry) {
        guard let data = try? Data(contentsOf: url) else { return }
        guard let object = try? JSONSerialization.jsonObject(with: data), let map = object as? [String: Any] else {
            problems.append("\(url.lastPathComponent) não é um objeto JSON; valem os atalhos padrão")
            return
        }
        applyPreferences(map, registry: registry)
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
