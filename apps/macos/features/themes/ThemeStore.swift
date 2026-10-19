import AppKit

/// The theme in use and who wants to know when it changes: the family the
/// user picked, in the mode they picked (following the system by default),
/// docs/spec/themes.md.
@MainActor
public final class ThemeStore {
    public static let shared = ThemeStore()

    /// Every theme the user can pick, in the order the settings show them.
    public private(set) var families: [ThemeFamily] = [.cadex]
    public private(set) var familyId = ThemeFamily.cadex.id
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

    public func setFamilies(_ list: [ThemeFamily]) {
        guard !list.isEmpty else { return }
        families = list
        refresh()
    }

    /// Picks a theme and a mode. An unknown id keeps the first family.
    public func select(id: String, mode: ThemeMode) {
        familyId = id
        self.mode = mode
        refresh()
    }

    public var family: ThemeFamily {
        families.first { $0.id == familyId } ?? families[0]
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
