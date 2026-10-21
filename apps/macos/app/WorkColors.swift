import AppKit
import CommandPalette
import Icons
import Strings
import Themes

/// Colors for spaces and tabs (plan 15, phase D): a name saved in
/// spaces.json, drawn as the theme's own ANSI color so it fits any theme.
/// The active tab's color, else the space's, else the accent paints the
/// window's tab bar and side panel (theme, accent, space, tab: each layer
/// over the one before).
enum WorkColor: String, CaseIterable {
    case red, yellow, green, cyan, blue, magenta

    var ansiIndex: Int {
        switch self {
        case .red: 1
        case .green: 2
        case .yellow: 3
        case .blue: 4
        case .magenta: 5
        case .cyan: 6
        }
    }

    var title: String {
        switch self {
        case .red: T("Red", "Vermelho")
        case .yellow: T("Yellow", "Amarelo")
        case .green: T("Green", "Verde")
        case .cyan: T("Cyan", "Ciano")
        case .blue: T("Blue", "Azul")
        case .magenta: T("Magenta", "Magenta")
        }
    }

    func rgb(in theme: Theme) -> RGB { theme.terminal.ansi[ansiIndex] }
}

extension WindowSession {
    /// space.set-color and tab.set-color.
    func registerWorkColors(palette: CommandPaletteController) {
        commands.register([
            Command(id: "space.set-color", title: T("Set Space Color", "Escolher a cor do space"),
                    keywords: ["space", "color", "cor", "paint", "pintar"], category: .tabs,
                    action: .run { [weak self] in
                        guard let spaces = self?.spaces else { return }
                        palette.open(WorkColorSource(current: spaces.activeColor) { spaces.setActiveColor($0) })
                    }),
            Command(id: "tab.set-color", title: T("Set Tab Color", "Escolher a cor da aba"),
                    keywords: ["tab", "aba", "color", "cor", "paint", "pintar"], category: .tabs,
                    action: .run { [weak self] in
                        guard let tabs = self?.tabs else { return }
                        palette.open(WorkColorSource(current: tabs.activeColor) { tabs.setActiveColor($0) })
                    }),
        ])
    }

    /// The window's accent from the active tab's color or the space's.
    func refreshWorkColor() {
        let name = tabs?.activeColor ?? spaces?.activeColor
        workspace?.workColor = name.flatMap(WorkColor.init(rawValue:))
    }
}

/// ⌘K's list of colors: none, then the six, the one in use marked.
@MainActor
final class WorkColorSource: PaletteSource {
    private let current: String?
    private let set: (String?) -> Void

    init(current: String?, set: @escaping (String?) -> Void) {
        self.current = current
        self.set = set
    }

    var placeholder: String { T("Choose a color", "Escolher uma cor") }
    var emptyText: String { T("No such color", "Nenhuma cor assim") }
    var icon: Icon { .palette }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        let options = [("", T("No Color", "Sem cor"))] + WorkColor.allCases.map { ($0.rawValue, $0.title) }
        let items = options
            .filter { query.isEmpty || $0.1.localizedCaseInsensitiveContains(query) || $0.0.contains(query.lowercased()) }
            .map { PaletteItem(id: $0.0, title: $0.1, detail: ($0.0.isEmpty ? nil : $0.0) == current ? T("in use", "em uso") : nil,
                               image: Self.swatch($0.0)) }
        show(items, nil)
    }

    /// A dot in the color as the theme draws it.
    private static func swatch(_ name: String) -> NSImage? {
        guard let color = WorkColor(rawValue: name)?.rgb(in: ThemeStore.shared.current) else { return nil }
        return NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            color.nsColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
            return true
        }
    }

    func choose(_ item: PaletteItem) {
        set(item.id.isEmpty ? nil : item.id)
    }

    func stop() {}
}
