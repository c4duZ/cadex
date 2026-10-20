import Strings
/// A theme as the user picks it: one name with a dark and/or a light
/// version (docs/spec/themes.md). The mode chooses which one shows.
public struct ThemeFamily: Equatable, Sendable, Identifiable {
    /// Stable, lowercase: "caffeine", "tokyo-night". Saved in settings.
    public let id: String
    public let name: String
    /// One line for the theme card.
    public let description: String
    public let dark: Theme?
    public let light: Theme?

    public init(id: String, name: String, description: String, dark: Theme?, light: Theme?) {
        self.id = id
        self.name = name
        self.description = description
        self.dark = dark
        self.light = light
    }

    /// The version for a mode, falling back to the one that exists.
    public func theme(dark wantsDark: Bool) -> Theme {
        (wantsDark ? dark ?? light : light ?? dark)!
    }
}

/// Which version of the theme shows: following the system, or fixed.
public enum ThemeMode: String, Sendable, CaseIterable {
    case system, dark, light
}

public extension ThemeFamily {
    /// The Cadex's own pair, until the catalog of plan 3, fase D.
    static let cadex = ThemeFamily(
        id: "cadex", name: "Cadex", description: T("Graphite gray around near-black panels.", "Cinza-grafite em volta de painéis quase pretos."),
        dark: .cadexDark, light: .cadexLight)
}
