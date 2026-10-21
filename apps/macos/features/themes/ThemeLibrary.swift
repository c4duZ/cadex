import Foundation
import Strings

/// Every theme the user can pick: theirs, from the themes folder
/// (Application Support/Cadex/themes, one Cadex theme file each), then the
/// built-in catalog. Read when asked, like the catalog (docs/spec/themes.md).
public enum ThemeLibrary {
    /// Ids of the user's themes start with this, so they never take a
    /// built-in one's place.
    public static let userPrefix = "user:"

    /// CADEX_THEMES_DIR points elsewhere (the tests).
    public static var folder: URL {
        if let path = ProcessInfo.processInfo.environment["CADEX_THEMES_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Cadex/themes")
    }

    /// The user's themes then the built-in ones; `problems` names each
    /// file of the folder that could not be read, and why.
    public static func all() -> (families: [ThemeFamily], problems: [String]) {
        let user = userThemes()
        return (user.families + ThemeCatalog.all(), user.problems)
    }

    public static func family(id: String) -> ThemeFamily? {
        if id.hasPrefix(userPrefix) {
            return userThemes().families.first { $0.id == id }
        }
        return ThemeCatalog.family(id: id)
    }

    static func userThemes() -> (families: [ThemeFamily], problems: [String]) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var families: [ThemeFamily] = [], problems: [String] = []
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension == "json" {
            do {
                let theme = try ThemeFile.read(try Data(contentsOf: file))
                families.append(ThemeFamily(id: userPrefix + file.deletingPathExtension().lastPathComponent, name: theme.name,
                                            description: T("Your theme: \(file.lastPathComponent)", "Seu tema: \(file.lastPathComponent)"),
                                            source: "user", dark: theme.dark ? theme : nil, light: theme.dark ? nil : theme))
            } catch {
                problems.append("\(file.lastPathComponent): \(error)")
            }
        }
        return (families, problems)
    }

    /// Saves `theme` in the folder under a file name from its name, and
    /// returns its id. A theme of the same name is replaced.
    public static func save(_ theme: Theme) throws -> String {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let slug = theme.name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        let name = slug.isEmpty ? "theme" : slug
        try ThemeFile.write(theme).write(to: folder.appendingPathComponent(name + ".json"), options: .atomic)
        return userPrefix + name
    }
}
