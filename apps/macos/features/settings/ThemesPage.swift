import AppKit
import Strings
import Themes
import UniformTypeIdentifiers

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
        let mode = SettingsPage.popup([(T("Follow the system", "Seguir o sistema"), "system"), (T("Dark", "Escuro"), "dark"), (T("Light", "Claro"), "light")],
                                      selected: appearance.mode) { [store] value in store.update { $0.appearance.mode = value } }
        cards = ThemeStore.shared.families.map { family in
            ThemeCard(family: family, selected: family.id == appearance.theme) { [weak self] id in self?.pick(id) }
        }
        var rows: [NSView] = [
            SettingsPage.row(T("Mode", "Modo"),
                             T("Which version of the theme shows: the one for the system's light or dark mode, or always the same.",
                               "Qual versão do tema aparece: a do modo claro ou escuro do sistema, ou sempre a mesma."),
                             control: mode),
            SettingsPage.section(T("Theme", "Tema")),
        ]
        rows += stride(from: 0, to: cards.count, by: 2).map { i in
            let pair = NSStackView(views: Array(cards[i..<min(i + 2, cards.count)]))
            pair.distribution = .fillEqually
            pair.spacing = 10
            if cards.count - i == 1 { pair.addArrangedSubview(NSView()) }
            return pair
        }
        rows += looksRows()
        return SettingsPage.make(title: T("Themes", "Temas"), subtitle: T("The theme, the window's frame and a background image.", "O tema, a moldura da janela e uma imagem de fundo."), rows: rows)
    }

    /// Vibrancy and the background image: off by default, they cost
    /// compositing on every frame (docs/spec/themes.md).
    private func looksRows() -> [NSView] {
        let a = store.settings.appearance
        let image = a.backgroundImage.map { ($0 as NSString).lastPathComponent } ?? T("none", "nenhuma")
        let pick = SettingsPage.button(T("Choose image…", "Escolher imagem…")) { [weak self] in self?.pickImage() }
        let remove = SettingsPage.button(T("Remove", "Remover")) { [store] in
            if let old = store.settings.appearance.backgroundImage { try? FileManager.default.removeItem(atPath: old) }
            store.update { $0.appearance.backgroundImage = nil }
        }
        remove.isEnabled = a.backgroundImage != nil
        let buttons = NSStackView(views: [remove, pick])
        buttons.spacing = 6
        return [
            SettingsPage.section(T("Window", "Janela")),
            SettingsPage.row(T("Vibrancy", "Vibrância"),
                             T("The window's frame turns frosted over what is behind it. The panels stay solid.",
                               "A moldura da janela fica fosca sobre o que está atrás dela. Os painéis continuam sólidos."),
                             control: SettingsPage.toggle(a.vibrancy) { [store] on in store.update { $0.appearance.vibrancy = on } }),
            SettingsPage.row(T("Background image", "Imagem de fundo"),
                             T("Shown behind the terminal; Cadex keeps a copy. Now: \(image).", "Aparece atrás do terminal; o Cadex guarda uma cópia. Agora: \(image)."),
                             control: buttons),
            SettingsPage.row(T("Image opacity", "Opacidade da imagem"), nil,
                             control: SettingsPage.slider(a.backgroundOpacity, range: 0...1, format: "%.0f%%", shown: { $0 * 100 }) { [store] value in
                                 store.update { $0.appearance.backgroundOpacity = value }
                             }),
            SettingsPage.row(T("Image blur", "Desfoque da imagem"), nil,
                             control: SettingsPage.slider(a.backgroundBlur, range: 0...50, format: "%.0f") { [store] value in
                                 store.update { $0.appearance.backgroundBlur = value }
                             }),
        ]
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let copy = try? BackgroundImages.keepCopy(of: url) else { NSSound.beep(); return }
        if let old = store.settings.appearance.backgroundImage { try? FileManager.default.removeItem(atPath: old) }
        store.update { $0.appearance.backgroundImage = copy }
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
        name.textColor = SettingsColors.text
        let line = NSTextField(labelWithString: family.description)
        line.font = .systemFont(ofSize: 11)
        line.textColor = SettingsColors.secondaryText
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
        layer?.borderColor = (selected ? SettingsColors.accent : SettingsColors.border).cgColor
        layer?.backgroundColor = SettingsColors.box.cgColor
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
