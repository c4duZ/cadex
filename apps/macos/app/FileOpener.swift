import AppKit
import Editor
import Tabs
import Terminal
import Themes

/// Where a chosen file opens (explorer, ⌘P, ⌘⇧F): an editor tab for text,
/// the system's default app for what the viewers do not show yet. Media
/// viewers join with plan 5, phase D.
@MainActor
final class FileOpener {
    private weak var tabs: TabsController?

    init(tabs: TabsController) {
        self.tabs = tabs
    }

    /// Opens `path`, at a 1-based line when given.
    func open(_ path: String, line: Int? = nil) {
        guard let tabs else { return }
        let document = (tabs.document(identity: path) as? EditorDocument) ?? makeEditor(path)
        tabs.open(document)
        if let line {
            // After the tab is in the window, so the view has its size.
            DispatchQueue.main.async { document.reveal(line: line) }
        }
    }

    private func makeEditor(_ path: String) -> EditorDocument {
        let document = EditorDocument(path: path)
        document.openExternally = { NSWorkspace.shared.open(URL(fileURLWithPath: $0)) }
        return document
    }

    /// Folders changed on disk: open files in them read themselves again.
    func foldersChanged(_ folders: [String]) {
        guard let tabs else { return }
        let changed = Set(folders)
        for case let editor as EditorDocument in tabs.allDocuments {
            let folder = (editor.path as NSString).deletingLastPathComponent
            if changed.contains(folder) { editor.diskMayHaveChanged() }
        }
    }
}

/// The editor's font and colors: the terminal's font and the theme's
/// terminal palette, so code reads like the terminal next to it.
@MainActor
enum EditorLooks {
    static func update(theme: Theme, font: NSFont) {
        let t = theme.terminal
        let ui = theme.interface
        EditorAppearance.current = EditorAppearance(
            font: font, background: t.background.nsColor, foreground: t.foreground.nsColor,
            currentLine: t.foreground.color(alpha: 0.06), lineNumber: ui.secondaryText.color(alpha: 0.7),
            selection: t.selection.color(alpha: 0.45),
            tokens: EditorAppearance.tokens(ansi: t.ansi.map(\.value), foreground: t.foreground.value))
    }

    /// As the terminal picks it: "SF Mono" (or a missing family) is the
    /// system's monospaced font.
    static func font(family: String, size: CGFloat) -> NSFont {
        if family != "SF Mono", let font = NSFont(name: family, size: size) { return font }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// From the current theme and terminal preferences.
    static func refresh() {
        let prefs = TerminalPreferences.current
        update(theme: ThemeStore.shared.current, font: font(family: prefs.fontFamily, size: prefs.fontSize))
    }
}
