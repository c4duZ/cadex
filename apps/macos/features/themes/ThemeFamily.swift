import Strings
/// A theme as the user picks it: one name with a dark and/or a light
/// version (docs/spec/themes.md). The mode chooses which one shows.
public struct ThemeFamily: Equatable, Sendable, Identifiable {
    /// Stable, lowercase: "caffeine", "tokyo-night". Saved in settings.
    public let id: String
    public let name: String
    /// One line for the theme card, in the interface's language.
    public let description: String
    /// Where the colors come from: "official", "tweakcn", "base16",
    /// "base24" or "user" (a file in the user's themes folder).
    public let source: String
    public let dark: Theme?
    public let light: Theme?

    public init(id: String, name: String, description: String, source: String = "official", dark: Theme?, light: Theme?) {
        self.id = id
        self.name = name
        self.description = description
        self.source = source
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
    /// The new frame's theme (docs/adr/0035-work-frame.md): only dark, as the
    /// mockups are; a light pair comes with a light mockup.
    static let cadexNight = ThemeFamily(
        id: "cadex-night", name: "Cadex Night",
        description: T("Neutral grays; color only for state. The new frame's own.", "Cinzas neutros; cor só para estado. O da moldura nova."),
        source: "cadex", dark: Theme.cadexNight, light: nil)
}
