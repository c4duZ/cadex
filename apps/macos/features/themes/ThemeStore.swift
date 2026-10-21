import AppKit

/// The theme in use and who wants to know when it changes (docs/spec/themes.md):
/// a theme for dark mode and one for light (the same family unless the user
/// picked two), the mode, the accent and high contrast. Only the families
/// in use are kept; the list of every theme is read when the settings or
/// ⌘K show it (ThemeLibrary).
@MainActor
public final class ThemeStore {
    public static let shared = ThemeStore()

    /// What the settings ask for (plan 15, phases B and C).
    public struct Choice: Equatable {
        public var dark: String
        public var light: String
        public var mode: ThemeMode
        /// In place of the theme's accent; nil keeps it.
        public var accent: RGB?
        public var highContrast: Bool

        public init(dark: String, light: String, mode: ThemeMode, accent: RGB? = nil, highContrast: Bool = false) {
            self.dark = dark
            self.light = light
            self.mode = mode
            self.accent = accent
            self.highContrast = highContrast
        }
    }

    public private(set) var choice = Choice(dark: ThemeFamily.cadex.id, light: ThemeFamily.cadex.id, mode: .system)
    public private(set) var darkFamily: ThemeFamily = .cadex
    public private(set) var lightFamily: ThemeFamily = .cadex
    public private(set) var current: Theme = .cadexDark
    private var observers: [(Theme) -> Void] = []
    private var appearanceObservation: NSKeyValueObservation?

    private init() {
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { _, _ in
            MainActor.assumeIsolated { ThemeStore.shared.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ThemeStore.shared.refresh() }
        }
        refresh()
    }

    /// Calls `observer` now and on every change.
    public func observe(_ observer: @escaping (Theme) -> Void) {
        observers.append(observer)
        observer(current)
    }

    /// The settings' choice. Unknown ids fall back to the default theme.
    public func apply(_ next: Choice) {
        if next.dark != darkFamily.id { darkFamily = Self.family(next.dark) }
        if next.light != lightFamily.id { lightFamily = next.light == darkFamily.id ? darkFamily : Self.family(next.light) }
        choice = next
        refresh()
    }

    /// One theme in both modes.
    public func select(id: String, mode: ThemeMode) {
        apply(Choice(dark: id, light: id, mode: mode, accent: choice.accent, highContrast: choice.highContrast))
    }

    /// The user's themes folder changed: a theme in use may be one of them.
    public func reload() {
        darkFamily = Self.family(darkFamily.id)
        lightFamily = Self.family(lightFamily.id)
        refresh()
    }

    /// The setting, or the system's "Increase contrast".
    public var isHighContrast: Bool {
        choice.highContrast || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    private static func family(_ id: String) -> ThemeFamily {
        ThemeLibrary.family(id: id) ?? ThemeCatalog.family(id: ThemeCatalog.defaultId) ?? .cadex
    }

    func refresh() {
        let wantsDark: Bool
        switch choice.mode {
        case .system: wantsDark = Self.systemIsDark
        case .dark: wantsDark = true
        case .light: wantsDark = false
        }
        var next = (wantsDark ? darkFamily : lightFamily).theme(dark: wantsDark)
        if let accent = choice.accent {
            next.interface.accent = accent
            next.interface.tabActive = next.interface.chrome.mixed(accent, 0.22)
        }
        if isHighContrast { next = next.withHighContrast() }
        guard next != current || observers.isEmpty else { return }
        current = next
        observers.forEach { $0(next) }
    }

    static var systemIsDark: Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
