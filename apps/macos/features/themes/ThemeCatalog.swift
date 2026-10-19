import Foundation

/// The themes that ship with the app: Resources/catalog.json, built by
/// tools/themes/build_catalog.py from the tweakcn presets and the official
/// palettes of open-source themes (docs/spec/themes.md, NOTICE).
public enum ThemeCatalog {
    /// The family the app starts with: the one the owner uses in Terax.
    public static let defaultId = "caffeine"

    /// Every built-in family, the default first. Empty only if the bundled
    /// file is missing or broken, which the tests catch.
    public static let builtIn: [ThemeFamily] = {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? read(data)) ?? []
    }()

    static func read(_ data: Data) throws -> [ThemeFamily] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["families"] as? [[String: Any]] else {
            throw ThemeFile.Problem(field: "families", message: "falta a lista de temas")
        }
        return try list.map { entry in
            guard let id = entry["id"] as? String, let name = entry["name"] as? String else {
                throw ThemeFile.Problem(field: "families", message: "tema sem id ou nome")
            }
            func version(_ key: String, dark: Bool) throws -> Theme? {
                guard let object = entry[key] as? [String: Any] else { return nil }
                return try ThemeFile.variant(object, name: name, dark: dark, prefix: "\(id).\(key).")
            }
            return ThemeFamily(id: id, name: name, description: entry["description"] as? String ?? "",
                               dark: try version("dark", dark: true), light: try version("light", dark: false))
        }
    }
}
