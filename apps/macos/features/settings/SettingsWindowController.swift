import AppKit
import UILooks
import CommandPalette
import Customize
import Icons
import Shortcuts
import Strings
import Themes

/// The settings window (⌘,): the sections in a list on the left with a search over every row, the
/// page on the right (plan 32 A; it was General, Terminal, Themes, Shortcuts and About as tabs, with
/// most modules in one long General). The status bar's items and the accounts (the Customize
/// window's lists) are sections here. One window, brought back if open (docs/spec/settings.md).
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: SettingsStore
    private let shortcuts: ShortcutsPage
    private let themes: ThemesPage
    private var window: NSWindow?
    private let navigation = SettingsNavigation()
    private(set) var selected = SettingsSection.general
    private var query = ""
    private let content = NSView()
    /// The lists to arrange, from the app: "statusBar" and "accounts" (the Customize pages).
    public var customizePages: () -> [CustomizePage] = { [] }
    private var shownLists: [String: CustomizePageView] = [:]
    /// Reopens Cadex (the language counts at launch).
    private let relaunch: () -> Void

    public init(store: SettingsStore, registry: CommandRegistry, keymap: @escaping () -> Keymap,
                suspendShortcuts: @escaping (Bool) -> Void, relaunch: @escaping () -> Void) {
        self.store = store
        self.relaunch = relaunch
        shortcuts = ShortcutsPage(store: store, registry: registry, keymap: keymap, suspendShortcuts: suspendShortcuts)
        themes = ThemesPage(store: store)
    }

    /// The command that opens this window.
    public var openCommand: Command {
        Command(id: "settings.open", title: T("Open settings", "Abrir configurações"), keywords: ["settings", "preferências", "ajustes"],
                category: .app, defaultShortcut: "cmd+,", action: .run { [weak self] in self?.show() })
    }

    /// The settings' pages in ⌘K, so every option is a command away (ADR
    /// 0005, plan 15), and terminal.toggle-ligatures.
    public var pageCommands: [Command] {
        [Command(id: "settings.open-terminal", title: T("Open Terminal Settings", "Abrir configurações do terminal"),
                 keywords: ["font", "fonte", "line height", "altura da linha", "spacing", "espaçamento", "contrast", "contraste", "cursor"],
                 category: .app, action: .run { [weak self] in self?.show(section: "terminal") }),
         Command(id: "settings.open-themes", title: T("Open Theme Settings", "Abrir configurações de temas"),
                 keywords: ["theme", "tema", "accent", "destaque", "contrast", "contraste", "background", "fundo"],
                 category: .app, action: .run { [weak self] in self?.show(section: "appearance") }),
         Command(id: "terminal.toggle-ligatures", title: T("Turn Ligatures On or Off", "Ligar ou desligar as ligaduras"),
                 keywords: ["ligatures", "ligaduras", "fira code", "font", "fonte"], category: .terminal,
                 action: .run { [store] in
                     store.update { $0.terminal.fontFeatures = TerminalTextRows.setLigatures(
                         !TerminalTextRows.ligatures.allSatisfy($0.terminal.fontFeatures.contains), in: $0.terminal.fontFeatures) }
                 })]
    }

    /// `section` (a SettingsSection's id: "memory", "statusBar") shows that page; nil keeps the one
    /// open (⌘,).
    public func show(section: String? = nil) {
        let window = self.window ?? makeWindow()
        self.window = window
        if let section, let found = SettingsSection(rawValue: section) {
            navigation.clearSearch()
            query = ""
            select(found)
        } else if !window.isVisible {
            select(selected)
        }
        window.makeKeyAndOrderFront(nil)
    }

    /// The lists changed elsewhere (⌘K, another window): an open list shows it.
    public func refreshLists() {
        guard window?.isVisible == true else { return }
        for page in customizePages() { shownLists[page.id]?.refresh(page) }
    }

    private func makeWindow() -> NSWindow {
        let width = UILooks.pt(DesignTokens.Inspector.width) * 3 / 4 + UILooks.pt(DesignTokens.Sheet.newTaskWidth + DesignTokens.Project.padding.left * 4)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: UILooks.pt(DesignTokens.Sheet.newTaskWidth) * 9 / 8),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: true)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = T("Settings", "Configurações")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: width * 3 / 4, height: UILooks.pt(DesignTokens.Sheet.newTaskWidth) * 2 / 3)
        // Over the app when it is in full screen, in the same Space: a plain
        // window opened in another Space and took the user out of the app
        // (owner's report, 2026-10-20). Auxiliary windows also cannot go
        // full screen themselves.
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.delegate = self
        navigation.onPick = { [weak self] section in
            self?.query = ""
            self?.select(section)
        }
        navigation.onSearch = { [weak self] words in
            guard let self else { return }
            self.query = words.trimmingCharacters(in: .whitespaces)
            self.query.isEmpty ? self.select(self.selected) : self.showResults()
        }
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = DesignTokens.Inspector.borderLeft.cgColor
        let root = NSView()
        for view in [navigation, line, content] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            navigation.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            navigation.topAnchor.constraint(equalTo: root.topAnchor), navigation.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: navigation.trailingAnchor), line.widthAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline),
            line.topAnchor.constraint(equalTo: root.topAnchor), line.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: UILooks.pt(DesignTokens.TitleBar.height) / 2),
            content.leadingAnchor.constraint(equalTo: line.trailingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        window.contentView = root
        root.wantsLayer = true
        root.layer?.backgroundColor = SettingsColors.background.cgColor
        window.center()
        ThemeStore.shared.observe { [weak self] _ in self?.themeChanged() }
        return window
    }

    /// The window follows the theme like the rest of the app; the open page
    /// is rebuilt with the new colors.
    private func themeChanged() {
        guard let window else { return }
        window.appearance = NSAppearance(named: SettingsColors.isDark ? .darkAqua : .aqua)
        window.backgroundColor = SettingsColors.background
        // On the content too: the window's own color left a lighter grey under the pages.
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = SettingsColors.background.cgColor
        if window.isVisible { query.isEmpty ? select(selected) : showResults() }
    }

    /// The rows of a section made of rows; nil for the pages of their own.
    func rows(of section: SettingsSection) -> [NSView]? {
        switch section {
        case .general: SectionRows.general(store) { [weak self] language in self?.askRelaunch(language) }
        case .terminal: TerminalPage.rows(store)
        case .files: SectionRows.files(store)
        case .git: SectionRows.git(store)
        case .agents: SectionRows.agents(store) + list("accounts", note: true)
        case .notifications: SectionRows.notifications(store)
        case .memory: MemoryRows.make(store) + MemoryRows.turnOff(store)
        case .orchestration: OrchestrationRows.make(store)
        case .machines: SectionRows.machines(store)
        case .statusBar: list("statusBar", note: false)
        case .appearance, .shortcuts, .about: nil
        }
    }

    /// A Customize list (the accounts, the status bar's items) as rows: its note and its list, whose
    /// own headers name it ("Accounts", "Left", "Right").
    private func list(_ id: String, note: Bool) -> [NSView] {
        guard let page = customizePages().first(where: { $0.id == id }) else { return [] }
        let view = CustomizePageView(page)
        shownLists[id] = view
        var views: [NSView] = []
        // Among other rows (the accounts) the note says what the list is; alone, the section's
        // subtitle already does (the status bar's said it twice).
        if note, !page.note.isEmpty { views.append(SettingsPage.note(page.note)) }
        return views + [view]
    }

    private func select(_ section: SettingsSection) {
        // Rebuilding the same page (a theme change) keeps where it was
        // scrolled, or picking a card would jump the list to the top.
        let sameSection = selected == section
        let scrolled = (content.subviews.first as? NSScrollView)?.contentView.bounds.origin
        selected = section
        navigation.show(section)
        shownLists = [:]
        let page: NSView
        switch section {
        case .appearance: page = themes.makeView()
        case .shortcuts: page = shortcuts.makeView()
        case .about: page = GeneralPages.about()
        default: page = SettingsPage.make(title: section.title, subtitle: section.subtitle, rows: rows(of: section) ?? [])
        }
        place(page)
        if sameSection, let scrolled, let scroll = page as? NSScrollView {
            content.layoutSubtreeIfNeeded()
            scroll.contentView.scroll(to: scrolled)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    /// Every row that has the words typed, under its section's name.
    private func showResults() {
        navigation.show(nil)
        shownLists = [:]
        var found: [NSView] = []
        for section in SettingsSection.allCases {
            let matches = (rows(of: section) ?? []).compactMap { $0 as? SettingsRowBox }.filter { $0.matches(query) }
            let named = section.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            guard !matches.isEmpty || named else { continue }
            found.append(SettingsPage.section(section.title))
            found += matches.isEmpty ? [SettingsPage.note(T("Open the section from the list on the left.", "Abra a seção pela lista à esquerda."))] : matches
        }
        if found.isEmpty { found = [SettingsPage.note(T("No setting has these words.", "Nenhuma configuração tem essas palavras."))] }
        place(SettingsPage.make(title: T("Search", "Busca"), subtitle: "“\(query)”", rows: found))
    }

    private func place(_ page: NSView) {
        content.subviews.forEach { $0.removeFromSuperview() }
        page.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(page)
        NSLayoutConstraint.activate([
            page.topAnchor.constraint(equalTo: content.topAnchor),
            page.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            page.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    /// The language, the interface's size and font count when Cadex opens:
    /// offer to reopen now, asked in the language just chosen (nil: the
    /// size or font changed, asked in the current one).
    private func askRelaunch(_ language: String?) {
        guard let window, window.attachedSheet == nil else { return }
        let pt = (language ?? store.settings.general.language) == "pt"
        let alert = NSAlert()
        alert.messageText = language == nil ? (pt ? "Reabrir o Cadex com a nova interface?" : "Reopen Cadex with the new interface?")
            : pt ? "Reabrir o Cadex em português?" : "Reopen Cadex in English?"
        alert.informativeText = pt ? "As abas e os projetos voltam como estão." : "Your tabs and projects come back as they are."
        alert.addButton(withTitle: pt ? "Reabrir agora" : "Reopen now")
        alert.addButton(withTitle: pt ? "Depois" : "Later")
        alert.beginSheetModal(for: window) { [weak self] answer in
            if answer == .alertFirstButtonReturn { self?.relaunch() }
        }
    }
}
