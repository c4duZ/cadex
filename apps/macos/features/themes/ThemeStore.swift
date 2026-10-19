import AppKit

/// The theme in use and who wants to know when it changes. Follows the
/// system's light or dark mode unless the user fixed a theme
/// (docs/spec/themes.md).
@MainActor
public final class ThemeStore {
    public static let shared = ThemeStore()

    public enum Choice: Equatable {
        case followSystem
        case fixed(Theme)
    }

    public private(set) var current: Theme = .cadexDark
    public var choice: Choice = .followSystem { didSet { refresh() } }
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

    func refresh() {
        let next: Theme
        switch choice {
        case .fixed(let theme): next = theme
        case .followSystem: next = Self.systemIsDark ? .cadexDark : .cadexLight
        }
        guard next != current || observers.isEmpty else { return }
        current = next
        observers.forEach { $0(next) }
    }

    static var systemIsDark: Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
