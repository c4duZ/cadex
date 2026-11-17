import AppKit
import Agents
import Icons
import SourceControl
import StatusBar
import Strings
import UILooks

/// The status bar items of the new frame (plan 26 phase B; docs/spec/status-bar.md;
/// docs/design/work-frame/screens.md, StatusBar): Project, Agents in two counts, Memory,
/// keep-awake and the update, the last two moved from the title bar. Every click runs a command
/// by id (ADR 0005).
extension WindowSession {
    /// "cadex · main ↑3": the project and its branch. Shown or not, the branch comes from the
    /// status the Changes panel already reads.
    func makeProjectItem() -> StatusItem {
        let label = StatusLabel(icon: nil, tip: T("The project and its branch", "O projeto e o branch dele"))
        // Room for two tab titles: a long branch is cut, not pushing the bar (owner, 2026-10-22).
        label.maxTextWidth = UILooks.pt(DesignTokens.Tab.maxTitle) * 2
        label.onClick = { [weak self] in _ = self?.commands.run("git.show") }
        projectLabel = label
        return StatusItem(id: "project", title: T("Project", "Projeto"),
                          subtitle: T("The project, its branch, commits to push ↑ and to pull ↓", "O projeto, o branch, commits a enviar ↑ e a receber ↓"),
                          icon: .folder, side: .left, view: label)
    }

    /// The project's name and the branch line, as either changes: the branch from git, the name
    /// when the folder changes (showLocation), with the branch last read.
    func showProject(branch: SourceControlController.Branch?) {
        lastBranch = branch
        let project = TitleBarView.location(of: folder.root).project
        projectLabel?.text = [project, branch.map(Self.branchText)].compactMap { $0 }.joined(separator: " · ")
    }

    /// "● 3 working  ● 2 need you": the blue and amber of the state glyph, a count left out when
    /// it is zero; read only while shown.
    func makeAgentsItem() -> StatusItem {
        let working = StatusLabel(icon: nil, tip: T("Agents working", "Agentes trabalhando"))
        let needs = StatusLabel(icon: nil, tip: T("Agents waiting for you", "Agentes esperando você"))
        working.dot = DesignTokens.Color.stateWorking
        needs.dot = DesignTokens.Color.stateNeeds
        // Nothing until the first count, and a zero count shows nothing (a bare dot said nothing).
        working.isHidden = true
        needs.isHidden = true
        needs.onClick = { [weak self] in _ = self?.commands.run("agents.show-attention") }
        working.onClick = { [weak self] in _ = self?.commands.run("agents.show") }
        let row = NSStackView(views: [working, needs])
        row.isHidden = true
        row.spacing = UILooks.pt(DesignTokens.StatusBar.gap) - 2 * StatusBarView.itemInset
        let item = StatusItem(id: "agents", title: T("Agents", "Agentes"),
                              subtitle: T("How many work and how many need you", "Quantos trabalham e quantos precisam de você"),
                              icon: .sparkle, side: .left, view: row)
        var token: UUID?
        item.onVisible = { [weak working, weak needs, weak row] visible in
            if visible {
                token = AgentsController.shared.watch {
                    let counts = AgentsController.shared.counts
                    working?.text = T("\(counts.working) working", "\(counts.working) trabalhando")
                    needs?.text = T("\(counts.waiting) need you", "\(counts.waiting) precisam de você")
                    working?.isHidden = counts.working == 0
                    needs?.isHidden = counts.waiting == 0
                    // Both zero: the item takes no room, or the bar showed a double gap.
                    row?.isHidden = counts.working == 0 && counts.waiting == 0
                }
            } else if let id = token {
                AgentsController.shared.stop(id)
                token = nil
            }
        }
        return item
    }

    /// "Memory": opens the project's memory (memory.show). The page count of the mockup waits for
    /// a cheap way to read it (the wiki is not read with the item alone).
    func makeMemoryItem() -> StatusItem {
        let label = StatusLabel(icon: nil, tip: T("The project's memory", "A memória do projeto"))
        label.text = T("Memory", "Memória")
        label.onClick = { [weak self] in _ = self?.commands.run("memory.show") }
        return StatusItem(id: "memory", title: T("Memory", "Memória"),
                          subtitle: T("Opens the project's memory", "Abre a memória do projeto"),
                          icon: .memory, side: .right, view: label)
    }

    /// The coffee, always in sight as it was in the title bar: filled while on (power.toggle).
    func makeKeepAwakeItem() -> StatusItem {
        let label = StatusLabel(icon: .coffee, tip: T("Keep awake", "Manter acordado"))
        label.onClick = { [weak self] in _ = self?.commands.run("power.toggle") }
        keepAwakeLabel = label
        return StatusItem(id: "keepAwake", title: T("Keep awake", "Manter acordado"),
                          subtitle: T("The coffee: keeps the computer awake", "O café: mantém o computador acordado"),
                          icon: .coffee, side: .right, view: label)
    }

    /// "Update to 2.6", in the accent, only while there is one (app.check-for-updates).
    func makeUpdateItem() -> StatusItem {
        let label = StatusLabel(icon: .arrowCircleUp, tip: "")
        label.tint = DesignTokens.Color.stateWorking
        label.onClick = { [weak self] in _ = self?.commands.run("app.check-for-updates") }
        label.isHidden = true
        updateLabel = label
        return StatusItem(id: "update", title: T("Update", "Atualização"),
                          subtitle: T("Shows only when there is a new Cadex", "Só aparece com um Cadex novo"),
                          icon: .arrowCircleUp, side: .right, view: label)
    }

    /// Keep-awake's state: the coffee filled while on; the tip says the state.
    func showPower() {
        keepAwakeLabel?.setIcon(.coffee, filled: app.power.mode != .off)
        keepAwakeLabel?.setTip(app.powerTip)
    }

    /// The update item, only while there is one to install or finish.
    func showUpdate() {
        updateLabel?.isHidden = !app.updates.showsButton
        updateLabel?.text = app.updates.buttonTip
        updateLabel?.setTip(app.updates.buttonTip)
    }
}
