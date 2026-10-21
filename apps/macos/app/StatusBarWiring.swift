import AppKit
import Icons
import Settings
import SourceControl
import StatusBar
import Strings

/// The status bar's catalog in this window (docs/spec/status-bar.md): the
/// bar's own Folder and Environment, then Git branch, Terminals, RAM, CPU
/// and Cadex memory. Each item reads only while it can be seen; the sides
/// are statusBar.left and statusBar.right in settings.json.
extension WindowSession {
    func setUpStatusBar(_ bar: StatusBarView, git: SourceControlController) {
        let branch = StatusLabel(icon: .gitBranch, tip: T("Git branch", "Branch do Git"))
        branch.onClick = { [weak self] in _ = self?.commands.run("git.show") }
        let branchItem = StatusItem(id: "branch", title: T("Git branch", "Branch do Git"),
                                    subtitle: T("With commits to push ↑ and to pull ↓", "Com commits a enviar ↑ e a receber ↓"),
                                    icon: .gitBranch, side: .right, view: branch)
        // The panel reads the status anyway; the item only shows it.
        git.onBranch = { [weak branch, weak branchItem] info in
            guard let branch, branchItem?.isVisible == true else { return }
            branch.text = info.map { Self.branchText($0) } ?? ""
            branch.isHidden = info == nil
        }
        branchItem.onVisible = { [weak git] visible in if visible { git?.refresh() } }
        let terminals = StatusLabel(icon: .terminalWindow, tip: T("Open terminals", "Terminais abertos"))
        let terminalsItem = StatusItem(id: "terminals", title: T("Terminals", "Terminais"),
                                       subtitle: T("How many are open in this window", "Quantos estão abertos nesta janela"),
                                       icon: .terminalWindow, side: .right, view: terminals)
        terminalsItem.onVisible = { [weak self] visible in if visible { self?.countTerminals() } }
        self.terminalsLabel = terminals
        self.terminalsItem = terminalsItem
        bar.add([branchItem, terminalsItem, makeAgentsItem(), makeUsageItem()] + SystemItems.all { [weak self] in _ = self?.commands.run("statusBar.activity-monitor") })
        bar.run = { [weak self] id in _ = self?.commands.run(id) }
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
        let count = spaces?.spaces.reduce(0) { $0 + $1.tabs.terminalCount } ?? 0
        terminalsLabel?.text = "\(count)"
    }

    static func branchText(_ branch: SourceControlController.Branch) -> String {
        var text = branch.name
        if branch.ahead > 0 { text += " ↑\(branch.ahead)" }
        if branch.behind > 0 { text += " ↓\(branch.behind)" }
        return text
    }
}
