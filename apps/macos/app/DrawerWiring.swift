import AppKit
import CommandPalette
import Icons
import StatusBar
import Strings
import Tabs
import Terminal
import UILooks

/// The terminal drawer of this window (plan 30 C, done with plan 29's review; the Drawer mockup):
/// quick terminals that are no project's, in their own tabs, rising over the center from the
/// bottom. drawer.toggle (⌃`, and the status bar's "Terminal ⌃`") shows or hides it; the first
/// show opens a shell in the home folder; drawer.move-to-project (⌘↩, only with the drawer's
/// terminal focused) takes it to the project shown, its shell going on. Not saved: they are
/// quick ones.
extension WindowSession {
    func drawerCommands() -> [Command] {
        [Command(id: "drawer.toggle", title: T("Show or Hide the Terminal Drawer", "Mostrar ou esconder a gaveta de terminais"),
                 keywords: ["drawer", "terminal", "quick", "gaveta", "rápido"], category: .terminal, defaultShortcut: "ctrl+`",
                 action: .run { [weak self] in self?.toggleDrawer() }),
         Command(id: "drawer.move-to-project", title: T("Move the Drawer's Terminal to the Project", "Levar o terminal da gaveta ao projeto"),
                 keywords: ["drawer", "move", "project", "task", "gaveta", "mover", "projeto"], category: .terminal, defaultShortcut: "cmd+return",
                 action: .run { [weak self] in self?.moveDrawerTerminal() },
                 unavailableReason: { [weak self] in
                     self?.drawerHasFocus == true ? nil : T("The drawer's terminal has no focus", "O terminal da gaveta não tem o foco")
                 })]
    }

    /// The keyboard is in the drawer's terminal.
    var drawerHasFocus: Bool {
        guard let drawer, drawer.superview != nil, let responder = window.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: drawer)
    }

    func toggleDrawer() {
        guard let workspace else { return }
        if let drawer, drawer.superview != nil {
            drawer.tabs.setShown(false)
            workspace.showDrawer(nil)
            tabs?.activeTerminal.map { window.makeFirstResponder($0) }
            return
        }
        let drawer = self.drawer ?? makeDrawer()
        self.drawer = drawer
        if drawer.tabs.count == 0 { drawer.tabs.newTab(cwd: NSHomeDirectory()) }
        workspace.showDrawer(drawer)
        drawer.tabs.setShown(true)
        drawer.tabs.activeTerminal.map { window.makeFirstResponder($0) }
    }

    private func makeDrawer() -> DrawerView {
        let tabs = TabsController(window: window)
        tabs.runCommand = { [weak self] id in self?.commands.run(id) ?? false }
        tabs.plainPanes = true
        tabs.bar.style = workspace?.titleBar.tabBar?.style ?? tabs.bar.style
        let toggle = app.keymapLabel("drawer.toggle") ?? "⌃`", move = app.keymapLabel("drawer.move-to-project") ?? "⌘↩"
        let drawer = DrawerView(tabs: tabs, hint: T("\(toggle) show or hide · drag up to resize · \(move) move to a task",
                                                   "\(toggle) mostra ou esconde · arraste para cima · \(move) leva a uma tarefa"))
        // The last quick terminal closed: the drawer goes, ready for the next.
        tabs.onEmpty = { [weak self] in
            self?.workspace?.showDrawer(nil)
            self?.drawer = nil
        }
        drawer.onResize = { [weak self] in self?.workspace?.showDrawer(drawer) }
        return drawer
    }

    /// ⌘↩ in the drawer: its terminal goes to the project shown, in a tab of its own.
    func moveDrawerTerminal() {
        guard let drawer, let terminal = drawer.tabs.takeFocusedTerminal(), let tabs else { return }
        tabs.adopt(terminal)
        window.makeFirstResponder(terminal)
    }

    /// "Terminal ⌃`" on the status bar's right (the mockups).
    func makeDrawerItem() -> StatusItem {
        let label = StatusLabel(icon: nil, tip: T("The terminal drawer", "A gaveta de terminais"))
        label.text = T("Terminal ", "Terminal ") + (app.keymapLabel("drawer.toggle") ?? "⌃`")
        label.onClick = { [weak self] in _ = self?.commands.run("drawer.toggle") }
        return StatusItem(id: "drawer", title: T("Terminal drawer", "Gaveta de terminais"),
                          subtitle: T("Quick terminals outside the projects", "Terminais rápidos fora dos projetos"),
                          icon: .terminal, side: .right, view: label)
    }
}
