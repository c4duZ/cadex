import AppKit
import Icons
import Menus
import Strings

/// The pane headers of every tab (PaneHeaderView.swift): what each one
/// says, and its buttons, which focus their pane and run a command by id
/// (ADR 0005): pane.close, pane.zoom; the "+" menu is the app's (paneMenu). Apart from
/// TabsController.swift, at its size limit.
extension TabsController {
    func wireHeaders(_ tab: Tab) {
        tab.layout.headerStyle = bar.style
        tab.layout.describe = { [weak self, weak tab] id in
            guard let self, let pane = tab?.panes[id] else { return nil }
            return self.headerInfo(pane)
        }
        tab.layout.onHeaderAction = { [weak self, weak tab] id, action in
            guard let self, let tab else { return }
            if case .drag(let phase, let point) = action { return tab.layout.dragPane(id, phase, at: point) }
            tab.focus(id)
            self.refreshBar()
            switch action {
            case .focus: break
            case .close: self.run("pane.close") { self.closeFocusedPane() }
            case .zoom: self.run("pane.zoom") { self.toggleZoom() }
            case .menu(let anchor): PopupMenu.show(self.paneMenu?() ?? [], below: anchor)
            case .drag: break
            }
        }
    }

    /// A pane's title and icon: a terminal's program, else its folder; a
    /// document's name and file icon, with a dot when unsaved.
    func headerInfo(_ pane: Pane) -> PaneHeaderView.Info {
        switch pane {
        case .terminal(let terminal):
            let program = terminal.programTitle
            return .init(title: program.isEmpty ? folderTitle(terminal.currentDirectory, home: home) : program, icon: .terminalWindow)
        case .document(let document):
            let (icon, color) = Self.tabIcon(for: document.identity)
            return .init(title: document.title, icon: icon, iconColor: color, image: Self.tabImage(for: document.identity),
                         dirty: document.hasUnsavedChanges)
        }
    }

    func refreshHeaders() {
        for tab in tabs.values {
            tab.layout.headerStyle = bar.style
        }
    }

    /// pane.zoom: the focused pane takes the whole tab, or gives it back.
    public func toggleZoom() {
        guard let tab = activeTab, tab.tree.leaves.count > 1 || tab.layout.zoomed != nil else { return }
        tab.layout.zoomed = tab.layout.zoomed == nil ? tab.focusedPane : nil
        tab.focusContent()
        refreshBar()
    }

    public var activePaneZoomed: Bool { activeTab?.layout.zoomed != nil }

    /// The command by id, or `fallback` where no registry runs it (tests).
    private func run(_ command: String, fallback: () -> Void) {
        if runCommand?(command) != true { fallback() }
    }
}
