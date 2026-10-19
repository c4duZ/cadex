import Foundation

/// The Cadex theme file (docs/spec/themes.md): JSON with the interface and
/// terminal colors, as "#RRGGBB". Reading it checks every field and says
/// which one is wrong.
///
///     { "name": "Meu tema", "dark": true,
///       "interface": { "chrome": "#252525", "panel": "#161616", ... },
///       "terminal": { "background": "#161616", ..., "ansi": [16 colors] } }
public enum ThemeFile {
    public struct Problem: Error, Equatable, CustomStringConvertible {
        public let field: String
        public let message: String
        public var description: String { "\(field): \(message)" }
    }

    static let interfaceFields = ["chrome", "panel", "panelBorder", "tabActive", "field", "text", "secondaryText", "accent"]
    static let terminalFields = ["background", "foreground", "cursor", "selection"]

    public static func read(_ data: Data) throws -> Theme {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Problem(field: "(arquivo)", message: "não é um objeto JSON")
        }
        guard let name = root["name"] as? String, !name.isEmpty else {
            throw Problem(field: "name", message: "falta o nome do tema")
        }
        return try variant(root, name: name, dark: root["dark"] as? Bool ?? true, prefix: "")
    }

    /// The interface and terminal sections of `object` as a theme. `prefix`
    /// goes before field names in problems ("dark." in the catalog).
    static func variant(_ object: [String: Any], name: String, dark: Bool, prefix: String) throws -> Theme {
        let ui = try section(object, prefix + "interface")
        let term = try section(object, prefix + "terminal")
        func color(_ section: [String: Any], _ group: String, _ key: String) throws -> RGB {
            try parse(section[key], field: "\(prefix)\(group).\(key)")
        }
        guard let ansiList = term["ansi"] as? [Any] else {
            throw Problem(field: prefix + "terminal.ansi", message: "faltam as 16 cores ANSI")
        }
        guard ansiList.count == 16 else {
            throw Problem(field: prefix + "terminal.ansi", message: "são \(ansiList.count) cores; precisa de 16")
        }
        let ansi = try ansiList.enumerated().map { try parse($0.element, field: "\(prefix)terminal.ansi[\($0.offset)]") }
        return Theme(
            name: name, dark: dark,
            interface: .init(
                chrome: try color(ui, "interface", "chrome"), panel: try color(ui, "interface", "panel"),
                panelBorder: try color(ui, "interface", "panelBorder"), tabActive: try color(ui, "interface", "tabActive"),
                field: try color(ui, "interface", "field"), text: try color(ui, "interface", "text"),
                secondaryText: try color(ui, "interface", "secondaryText"), accent: try color(ui, "interface", "accent")),
            terminal: .init(
                background: try color(term, "terminal", "background"), foreground: try color(term, "terminal", "foreground"),
                cursor: try color(term, "terminal", "cursor"), selection: try color(term, "terminal", "selection"),
                ansi: ansi))
    }

    /// The file form of a theme, the inverse of `read`.
    public static func write(_ theme: Theme) -> Data {
        let ui = theme.interface, term = theme.terminal
        let object: [String: Any] = [
            "name": theme.name, "dark": theme.dark,
            "interface": [
                "chrome": ui.chrome.hex, "panel": ui.panel.hex, "panelBorder": ui.panelBorder.hex,
                "tabActive": ui.tabActive.hex, "field": ui.field.hex, "text": ui.text.hex,
                "secondaryText": ui.secondaryText.hex, "accent": ui.accent.hex,
            ],
            "terminal": [
                "background": term.background.hex, "foreground": term.foreground.hex, "cursor": term.cursor.hex,
                "selection": term.selection.hex, "ansi": term.ansi.map(\.hex),
            ],
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    /// "#RGB", "#RRGGBB" or "#RRGGBBAA" (the alpha is ignored).
    public static func parse(_ value: Any?, field: String) throws -> RGB {
        guard let text = value as? String else { throw Problem(field: field, message: "falta a cor") }
        var hex = Substring(text)
        guard hex.first == "#" else { throw Problem(field: field, message: "\"\(text)\" não é uma cor #RRGGBB") }
        hex = hex.dropFirst()
        if hex.count == 3 { hex = Substring(hex.map { "\($0)\($0)" }.joined()) }
        if hex.count == 8 { hex = hex.prefix(6) }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
            throw Problem(field: field, message: "\"\(text)\" não é uma cor #RRGGBB")
        }
        return RGB(value)
    }

    private static func section(_ root: [String: Any], _ key: String) throws -> [String: Any] {
        let name = String(key.split(separator: ".").last!)
        guard let section = root[name] as? [String: Any] else { throw Problem(field: key, message: "falta a seção") }
        return section
    }
}
