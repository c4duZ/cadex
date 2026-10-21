import AppKit

/// The theme in use and who wants to know when it changes: the family the
/// user picked, in the mode they picked (following the system by default),
/// docs/spec/themes.md. Only the family in use is kept; the list of every
/// theme is read when the settings or ⌘K show it (ThemeLibrary).
@MainActor
public final class ThemeStore {
    public static let shared = ThemeStore()

    public private(set) var family: ThemeFamily = .cadex
    public private(set) var mode = ThemeMode.system
    public private(set) var current: Theme = .cadexDark
    private var observers: [(Theme) -> Void] = []
    private var appearanceObservation: NSKeyValueObservation?

    private init() {
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { _, _ in
            MainActor.assumeIsolated { ThemeStore.shared.refresh() }
        }
        refresh()
    }

    /// Calls `observer` now and on every change.
    public func observe(_ observer: @escaping (Theme) -> Void) {
        observers.append(observer)
        observer(current)
    }

    /// Picks a theme and a mode. An unknown id falls back to the default.
    public func select(id: String, mode: ThemeMode) {
        if id != family.id {
            family = ThemeLibrary.family(id: id) ?? ThemeCatalog.family(id: ThemeCatalog.defaultId) ?? .cadex
        }
        self.mode = mode
        refresh()
    }

    /// The user's themes folder changed: the theme in use may be one of them.
    public func reload() {
        if let fresh = ThemeLibrary.family(id: family.id) { family = fresh }
        refresh()
    }

    func refresh() {
        let wantsDark: Bool
        switch mode {
        case .system: wantsDark = Self.systemIsDark
        case .dark: wantsDark = true
        case .light: wantsDark = false
        }
        let next = family.theme(dark: wantsDark)
        guard next != current || observers.isEmpty else { return }
        current = next
        observers.forEach { $0(next) }
    }

    static var systemIsDark: Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
