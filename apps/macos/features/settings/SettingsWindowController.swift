import AppKit
import CommandPalette
import Icons
import Shortcuts
import Strings
import Themes

/// The settings window (⌘,), after the Terax one: the sections as tabs at
/// the top, the page below. One window, brought back if open
/// (docs/spec/settings.md).
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let store: SettingsStore
    private let shortcuts: ShortcutsPage
    private let themes: ThemesPage
    private var window: NSWindow?
    private let tabs = NSSegmentedControl()
    private let content = NSView()
    private static let sections: [(title: String, icon: Icon)] = [
        (T("General", "Geral"), .gearSix), ("Terminal", .terminalWindow), (T("Themes", "Temas"), .palette), (T("Shortcuts", "Atalhos"), .keyboard), (T("About", "Sobre"), .info),
    ]
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

    public func show(section: Int = 0) {
        let window = self.window ?? makeWindow()
        self.window = window
        if !window.isVisible { select(section) }
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: true)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = T("Settings", "Configurações")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 420)
        // Over the app when it is in full screen, in the same Space: a plain
        // window opened in another Space and took the user out of the app
        // (owner's report, 2026-10-20). Auxiliary windows also cannot go
        // full screen themselves.
        window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        window.delegate = self

        tabs.segmentCount = Self.sections.count
        for (i, section) in Self.sections.enumerated() {
            tabs.setLabel(section.title, forSegment: i)
            tabs.setImage(section.icon.image(size: 14), forSegment: i)
            tabs.setImageScaling(.scaleNone, forSegment: i)
        }
        tabs.segmentStyle = .automatic
        tabs.trackingMode = .selectOne
        tabs.target = self
        tabs.action = #selector(tabChanged)

        let root = NSView()
        for view in [tabs, content] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            tabs.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            content.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 10),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        window.contentView = root
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
        tabs.selectedSegmentBezelColor = SettingsColors.accent
        if window.isVisible { select(tabs.selectedSegment) }
    }

    @objc private func tabChanged() {
        select(tabs.selectedSegment)
    }

    private func select(_ section: Int) {
        // Rebuilding the same page (a theme change) keeps where it was
        // scrolled, or picking a card would jump the list to the top.
        let sameSection = tabs.selectedSegment == section
        let scrolled = (content.subviews.first as? NSScrollView)?.contentView.bounds.origin
        tabs.selectedSegment = section
        let page: NSView
        switch section {
        case 1: page = TerminalPage.make(store)
        case 2: page = themes.makeView()
        case 3: page = shortcuts.makeView()
        case 4: page = GeneralPages.about()
        default: page = GeneralPages.general(store) { [weak self] language in self?.askRelaunch(language) }
        }
        content.subviews.forEach { $0.removeFromSuperview() }
        page.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(page)
        NSLayoutConstraint.activate([
            page.topAnchor.constraint(equalTo: content.topAnchor),
            page.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            page.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        if sameSection, let scrolled, let scroll = page as? NSScrollView {
            content.layoutSubtreeIfNeeded()
            scroll.contentView.scroll(to: scrolled)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    /// The language counts when Cadex opens: offer to reopen now, asked in
    /// the language just chosen.
    private func askRelaunch(_ language: String) {
        guard let window else { return }
        let pt = language == "pt"
        let alert = NSAlert()
        alert.messageText = pt ? "Reabrir o Cadex em português?" : "Reopen Cadex in English?"
        alert.informativeText = pt ? "As abas e os spaces voltam como estão." : "Your tabs and spaces come back as they are."
        alert.addButton(withTitle: pt ? "Reabrir agora" : "Reopen now")
        alert.addButton(withTitle: pt ? "Depois" : "Later")
        alert.beginSheetModal(for: window) { [weak self] answer in
            if answer == .alertFirstButtonReturn { self?.relaunch() }
        }
    }
}
