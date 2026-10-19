import AppKit
import Themes

/// The "Temas" page, after the Terax one: the mode, then a grid of theme
/// cards with a swatch, the name and one line about it. Picking a card
/// changes the theme at once (docs/spec/themes.md).
@MainActor
final class ThemesPage {
    private let store: SettingsStore
    private var cards: [ThemeCard] = []

    init(store: SettingsStore) {
        self.store = store
    }

    func makeView() -> NSView {
        let appearance = store.settings.appearance
        let mode = SettingsPage.popup([("Seguir o sistema", "system"), ("Escuro", "dark"), ("Claro", "light")],
                                      selected: appearance.mode) { [store] value in store.update { $0.appearance.mode = value } }
        cards = ThemeStore.shared.families.map { family in
            ThemeCard(family: family, selected: family.id == appearance.theme) { [weak self] id in self?.pick(id) }
        }
        var rows: [NSView] = [
            SettingsPage.row("Modo", "Qual versão do tema aparece: a do modo do sistema, ou sempre a mesma.", control: mode),
            SettingsPage.section("Tema"),
        ]
        rows += stride(from: 0, to: cards.count, by: 2).map { i in
            let pair = NSStackView(views: Array(cards[i..<min(i + 2, cards.count)]))
            pair.distribution = .fillEqually
            pair.spacing = 10
            if cards.count - i == 1 { pair.addArrangedSubview(NSView()) }
            return pair
        }
        return SettingsPage.make(title: "Temas", subtitle: "As cores do app e do terminal.", rows: rows)
    }

    private func pick(_ id: String) {
        store.update { $0.appearance.theme = id }
        cards.forEach { $0.selected = $0.family.id == id }
    }
}

/// One theme in the grid: three color bars on the theme's background, the
/// name and the description; outlined when it is the one in use.
final class ThemeCard: NSView {
    let family: ThemeFamily
    var selected: Bool { didSet { updateBorder() } }
    private let onPick: (String) -> Void

    init(family: ThemeFamily, selected: Bool, onPick: @escaping (String) -> Void) {
        self.family = family
        self.selected = selected
        self.onPick = onPick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        let theme = family.dark ?? family.light!
        let swatch = Swatch(theme: theme)
        let name = NSTextField(labelWithString: family.name)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        let line = NSTextField(labelWithString: family.description)
        line.font = .systemFont(ofSize: 11)
        line.textColor = .secondaryLabelColor
        line.lineBreakMode = .byTruncatingTail
        let texts = NSStackView(views: [name, line])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2
        let row = NSStackView(views: [swatch, texts])
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 62),
            swatch.widthAnchor.constraint(equalToConstant: 56),
            swatch.heightAnchor.constraint(equalToConstant: 42),
        ])
        updateBorder()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ThemeCard is created in code") }

    override func mouseDown(with event: NSEvent) {
        onPick(family.id)
    }

    private func updateBorder() {
        layer?.borderColor = (selected ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.borderWidth = selected ? 2 : 1
    }
}

/// The three bars of a card: accent, secondary text and text, on the
/// theme's background, as the Terax cards show.
private final class Swatch: NSView {
    private let theme: Theme

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Swatch is created in code") }

    override func draw(_ dirtyRect: NSRect) {
        theme.terminal.background.nsColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        let colors = [theme.interface.accent, theme.interface.secondaryText, theme.terminal.foreground]
        let width: CGFloat = 7, gap: CGFloat = 5
        let start = bounds.midX - (width * 3 + gap * 2) / 2
        for (i, color) in colors.enumerated() {
            color.nsColor.setFill()
            let bar = NSRect(x: start + CGFloat(i) * (width + gap), y: bounds.minY + 9, width: width, height: bounds.height - 18)
            NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3).fill()
        }
    }
}
