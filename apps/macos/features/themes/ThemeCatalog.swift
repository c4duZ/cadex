import Foundation
import Strings

/// The themes that ship with the app: Resources/catalog.json, built by
/// tools/themes/build_catalog.py from the official palettes of open-source
/// themes, the tweakcn presets and the base16/base24 schemes
/// (docs/spec/themes.md, NOTICE). Read when asked and not kept: the app
/// holds only the themes in use (plan 15: hundreds of themes must not
/// weigh on the app).
public enum ThemeCatalog {
    /// The family the app starts with: the one the owner uses.
    public static let defaultId = "caffeine"

    /// Every built-in family, the default first. Empty only if the bundled
    /// file is missing or broken, which the tests catch.
    public static func all() -> [ThemeFamily] {
        guard let entries = entries() else { return [] }
        return entries.compactMap { try? family($0) }
    }

    /// One built-in family, reading only its entry.
    public static func family(id: String) -> ThemeFamily? {
        guard let entry = entries()?.first(where: { $0["id"] as? String == id }) else { return nil }
        return try? family(entry)
    }

    private static func entries() -> [[String: Any]]? {
        // Contents/Resources in Cadex.app; Bundle.module in development (see
        // Icon.registerFont for why not Bundle.module in the app).
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json")
                ?? Bundle.module.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return root["families"] as? [[String: Any]]
    }

    static func read(_ data: Data) throws -> [ThemeFamily] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["families"] as? [[String: Any]] else {
            throw ThemeFile.Problem(field: "families", message: "falta a lista de temas")
        }
        return try list.map(family)
    }

    static func family(_ entry: [String: Any]) throws -> ThemeFamily {
        guard let id = entry["id"] as? String, let name = entry["name"] as? String else {
            throw ThemeFile.Problem(field: "families", message: "tema sem id ou nome")
        }
        func version(_ key: String, dark: Bool) throws -> Theme? {
            guard let object = entry[key] as? [String: Any] else { return nil }
            return try ThemeFile.variant(object, name: name, dark: dark, prefix: "\(id).\(key).")
        }
        // A pair since plan 15; a plain string before.
        let text = entry["description"] as? [String: String]
        let description = text.map { T($0["en"] ?? "", $0["pt"] ?? "") } ?? entry["description"] as? String ?? ""
        return ThemeFamily(id: id, name: name, description: description, source: entry["source"] as? String ?? "official",
                           dark: try version("dark", dark: true), light: try version("light", dark: false))
    }
}
