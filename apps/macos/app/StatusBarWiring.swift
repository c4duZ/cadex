import AppKit
import Icons
import Settings
import SourceControl
import StatusBar
import Strings
import UILooks

/// The status bar's catalog in this window (docs/spec/status-bar.md): the
/// bar's own Folder and Environment, then Git branch, Terminals, RAM, CPU
/// and Cadex memory. Each item reads only while it can be seen; the sides
/// are statusBar.left and statusBar.right in settings.json.
extension WindowSession {
    func setUpStatusBar(_ bar: StatusBarView, git: SourceControlController) {
        let branch = StatusLabel(icon: .gitBranch, tip: T("Git branch", "Branch do Git"))
        branch.maxTextWidth = UILooks.pt(180)
        branch.onClick = { [weak self] in _ = self?.commands.run("git.show") }
        let branchItem = StatusItem(id: "branch", title: T("Git branch", "Branch do Git"),
                                    subtitle: T("With commits to push ↑ and to pull ↓", "Com commits a enviar ↑ e a receber ↓"),
                                    icon: .gitBranch, side: .right, view: branch)
        // The panel reads the status anyway; the item only shows it.
        git.onBranch = { [weak self, weak branch, weak branchItem] info in
            self?.showPanelBranch(info)
            self?.showProject(branch: info)
            guard let branch, branchItem?.isVisible == true else { return }
            branch.text = info.map { Self.branchText($0) } ?? ""
            branch.toolTip = info.map { Self.branchText($0) }
            branch.isHidden = info == nil
        }
        branchItem.onVisible = { [weak git] visible in if visible { git?.refresh() } }
        let terminals = StatusLabel(icon: .terminalWindow, tip: T("Open terminals", "Terminais abertos"))
        attachCard(to: terminals) { [weak self] close in self?.terminalsCard(close: close) ?? NSView() }
        let terminalsItem = StatusItem(id: "terminals", title: T("Terminals", "Terminais"),
                                       subtitle: T("How many are open in this window", "Quantos estão abertos nesta janela"),
                                       icon: .terminalWindow, side: .right, view: terminals)
        terminalsItem.onVisible = { [weak self] visible in if visible { self?.countTerminals() } }
        self.terminalsLabel = terminals
        self.terminalsItem = terminalsItem
        bar.add([makeDrawerItem(), makeProjectItem(), branchItem, terminalsItem, makeAgentsItem(), makeMemoryItem(), makeUsageItem(),
                 makeKeepAwakeItem(), makeUpdateItem(), makePortsItem(), makeSSHItem(), makeTailscaleItem(), makeDockerItem()]
                + SystemItems.all(click: { [weak self] in _ = self?.commands.run("statusBar.activity-monitor") },
                                  terminals: { [weak self] in self?.cadexTerminals() ?? [] }))
        bar.run = { [weak self] id in _ = self?.commands.run(id) }
        attachItemCards(bar)
        bar.onLayoutChange = { [weak self] left, right in
            self?.settings.store.update {
                $0.statusBar.left = left
                $0.statusBar.right = right
            }
        }
        applyStatusBar(settings.store.settings.statusBar)
    }

    /// statusBar.left and statusBar.right, in this window.
    func applyStatusBar(_ prefs: Settings.StatusBar) {
        guard let bar = workspace?.statusBar, prefs.left != bar.left || prefs.right != bar.right else { return }
        for problem in bar.setLayout(left: prefs.left, right: prefs.right) { NSLog("Cadex settings: %@", problem) }
        refreshCustomize()
    }

    /// The Terminals item, when it shows: every terminal of every space.
    func countTerminals() {
        guard terminalsItem?.isVisible == true else { return }
        let count = projects?.projects.reduce(0) { $0 + $1.tabs.terminalCount } ?? 0
        terminalsLabel?.text = "\(count)"
    }

    static func branchText(_ branch: SourceControlController.Branch) -> String {
        var text = branch.name
        if branch.ahead > 0 { text += " ↑\(branch.ahead)" }
        if branch.behind > 0 { text += " ↓\(branch.behind)" }
        return text
    }

    /// Cadex's terminals with a program in front, in every window, for the system cards' "In
    /// Cadex": the program's group, "project", and the way to it.
    func cadexTerminals() -> [SystemCards.Terminal] {
        app.sessions.flatMap { window in
            (window.projects?.projects ?? []).flatMap { project in
                project.tabs.allTerminals.compactMap { terminal -> SystemCards.Terminal? in
                    let group = terminal.foregroundGroup
                    guard group > 0, group != terminal.shellPid else { return nil }
                    return SystemCards.Terminal(group: group, name: project.name) { [weak app] in app?.goToAgent(key: nil, pid: group) }
                }
            }
        }
    }
}
