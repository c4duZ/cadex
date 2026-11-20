import Agents
import AppKit
import UILooks
import CommandPalette
import Editor
import Explorer
import Icons
import Memory
import Strings
import Themes

/// The Memory page in this window (plan 22 phase H; docs/spec/memory.md,
/// "Página Memory"): what the page shows comes from `cadex memory-agent`
/// (overview, status, proposals) and the wiki folder, gathered only while
/// the page is on screen; its actions and commands run here.
extension WindowSession {
    func makeMemoryPage() -> MemoryView {
        let page = MemoryView()
        page.run = { [weak self] id in _ = self?.commands.run(id) }
        page.accountName = Self.accountName
        page.projectName = { [weak self] in self.map { TitleBarView.location(of: $0.folder.root).project } ?? "" }
        page.accountLogo = ProviderLogo.claude.image(size: 10)
        page.accountTint = ProviderLogo.claude.brandColor ?? DesignTokens.Color.textSecondary
        page.accountOf = { id in Self.historyEntry(session: id).map { Self.accountName($0.account) } }
        page.placeOf = { id in Self.historyEntry(session: id).map { ($0.cwd as NSString).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 } }
        page.canResume = { id in Self.historyEntry(session: id) != nil }
        page.isEmptySession = { id in Self.historyEntry(session: id).map { !$0.hasPrompt } ?? false }
        // The title of the session's conversation: the owner's (/rename), else the one Claude gave.
        page.titleOf = { id in
            Self.historyEntry(session: id).flatMap { entry in [entry.customTitle, entry.aiTitle].first { !$0.isEmpty } }
        }
        page.onShowing = { [weak self] shows in self?.memoryPageShowing(shows) }
        // A click opens the project's page on the line (plan 34 G): a session in Sessions with its
        // summary, any other page in Memory rendered; the raw .md is the page's Edit.
        page.onOpenPage = { [weak self] memoryPage in self?.openMemoryPage(memoryPage) }
        page.onOpenSession = { [weak self] id in self?.openMemorySession(id) }
        page.onReveal = { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: $0.path)]) }
        page.onDelete = { [weak self] memoryPage in self?.deleteMemoryPage(memoryPage) }
        page.onApprove = { [weak self] proposal in self?.decideProposal(proposal, approve: true) }
        page.onReject = { [weak self] proposal in self?.decideProposal(proposal, approve: false) }
        memoryPage = page
        return page
    }

    func memoryPageActions() -> MemoryPageActions {
        var actions = MemoryPageActions(
            // The project's memory is a section of its page now (ADR 0039).
            show: { [weak self] in
                guard let self, let folder = self.projects?.activeFolder else { return }
                self.openProjectPage(folder, section: .memory)
            },
            showBriefing: { [weak self] in self?.showMemoryBriefing() },
            reindex: { [weak self] in if let self { self.reindexMemory(root: self.projectRoot) } },
            refresh: { [weak self] in self?.refreshMemoryPage() },
            turnOn: { [weak self] in
                self?.settings.store.update { $0.memory.enabled = true }
                self?.refreshMemoryPage()
            },
            proposals: { [weak self] give in
                guard let self else { return give([]) }
                MemoryWiring.runAgent(["proposals", "--cwd", self.projectRoot]) { code, json in give(code == 0 ? MemoryProposal.parseList(json) : []) }
            },
            approve: { [weak self] proposal in self?.decideProposal(proposal, approve: true) },
            reject: { [weak self] proposal in self?.decideProposal(proposal, approve: false) })
        actions.showHistory = { [weak self] in self?.showMemoryHistory() }
        // By id (the Memória panel's buttons, `cadex run`): through the panel's route, then this page read again.
        actions.decide = { [weak self] id, approve, reason in
            guard let self else { return }
            let page = self.memoryPanelPage() ?? self.makeMemoryPanel()
            page.perform(approve ? .approve(id: id) : .reject(id: id, reason: reason)) { [weak self] in self?.refreshMemoryPage() }
        }
        // The tab's tree when it was read; otherwise the wiki read now, from projects.json: ⌘K may
        // come before the tab was ever opened (review of 2026-11-17).
        actions.pages = { [weak self] in
            guard let self else { return [] }
            if let tree = self.memoryPage?.state?.tree { return tree.allPages }
            guard let wiki = MemoryPageState.wikiDir(overview: nil, root: self.projectRoot, folder: MemoryKit.folder()),
                  FileManager.default.fileExists(atPath: wiki) else { return [] }
            return MemoryWiki.tree(wiki).allPages
        }
        actions.openPage = { [weak self] page in self?.openMemoryPage(page) }
        return actions
    }

    /// The wiki's commits (every page write, reindex and approval is one)
    /// in the Git History tab; the wiki is its own repository in the
    /// memory folder, authorized first as the core asks.
    private func showMemoryHistory() {
        let root = MemoryKit.folder() + "/wiki"
        guard FileManager.default.fileExists(atPath: root + "/.git"), WorkspaceFolder.allow(root) != nil else { return NSSound.beep() }
        opener?.openHistory(root)
    }

    /// On screen: the History watched (for the pages' accounts and "Open
    /// the Session") and the state read; off screen, both stop.
    private func memoryPageShowing(_ shows: Bool) {
        let history = AgentHistoryController.shared
        if shows {
            if memoryHistoryWatch == nil, history.isEnabled {
                memoryHistoryWatch = history.watch { [weak self] in self?.memoryPage?.reloadOrigins() }
            }
            refreshMemoryPage()
        } else if let watch = memoryHistoryWatch {
            history.stop(watch)
            memoryHistoryWatch = nil
        }
    }

    /// The page's state: overview (never starts the engine), the agent's
    /// status, the proposals when some wait, then the wiki read off the
    /// main thread. Nothing when the page is not on screen.
    func refreshMemoryPage() {
        guard let page = memoryPage, page.isShowing else { return }
        guard settings.store.settings.memory.enabled else { return page.show(MemoryPageState(enabled: false)) }
        let root = projectRoot
        MemoryWiring.runAgent(["overview", "--cwd", root]) { [weak self] code, json in
            let overview = code == 0 ? MemoryOverview.parse(json) : nil
            let problem = code == 0 ? nil : T("The memory agent did not answer: ", "O agente de memória não respondeu: ")
                + (json["error"] as? String ?? T("exit \(code)", "saída \(code)"))
            MemoryWiring.runAgent(["status"]) { [weak self] statusCode, statusJSON in
                let agent = statusCode == 0 ? MemoryAgentStatus.parse(statusJSON) : nil
                guard (agent?.proposalsPending ?? 0) > 0 else {
                    return self?.finishMemoryPage(root: root, overview: overview, agent: agent, proposals: [], problem: problem) ?? ()
                }
                MemoryWiring.runAgent(["proposals", "--cwd", root]) { [weak self] proposalsCode, proposalsJSON in
                    self?.finishMemoryPage(root: root, overview: overview, agent: agent,
                                           proposals: proposalsCode == 0 ? MemoryProposal.parseList(proposalsJSON) : [], problem: problem)
                }
            }
        }
    }

    private func finishMemoryPage(root: String, overview: MemoryOverview?, agent: MemoryAgentStatus?, proposals: [MemoryProposal], problem: String?) {
        let wiki = MemoryPageState.wikiDir(overview: overview, root: root, folder: MemoryKit.folder())
        DispatchQueue.global(qos: .userInitiated).async {
            let tree = wiki.flatMap { FileManager.default.fileExists(atPath: $0) ? MemoryWiki.tree($0) : nil }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    guard let self, self.projectRoot == root else { return }
                    self.memoryPage?.show(MemoryPageState(enabled: true, overview: overview, agent: agent, proposals: proposals,
                                                          wikiDir: wiki, tree: tree, problem: problem))
                }
            }
        }
    }

    /// A page in the Markdown tab; its folder authorized first, as the
    /// wiki lives outside the workspace (the core refuses files out of it).
    /// A memory page from the panel or ⌘K's memory search: the project's page on the line (plan 34
    /// G), a session in Sessions with its summary, any other page in Memory rendered; the raw .md is
    /// the page's Edit.
    private func openMemoryPage(_ page: MemoryPage) {
        guard let folder = projects?.activeFolder else { return }
        if page.relative.hasPrefix("sessions/"), let id = page.sessionID {
            openProjectPage(folder, section: .sessions, item: id)
        } else {
            openProjectPage(folder, section: .memory, item: page.path)
        }
    }

    /// "Open the Session": resumed in its account, as History does.
    private func openMemorySession(_ id: String) {
        guard let entry = Self.historyEntry(session: id) else { return NSSound.beep() }
        typeInNewTab(AgentHistoryLaunch.resume(entry), cwd: AgentHistoryLaunch.folder(entry))
    }

    static func historyEntry(session id: String) -> AgentHistoryEntry? {
        AgentHistoryController.shared.entries.first { $0.id == id }
    }

    private func deleteMemoryPage(_ page: MemoryPage) {
        let alert = NSAlert()
        alert.messageText = T("Delete the page \"\(page.title)\"?", "Apagar a página \"\(page.title)\"?")
        alert.informativeText = T("It leaves the project memory; the wiki's git history keeps it.",
                                  "Ela sai da memória do projeto; o histórico git da wiki a guarda.")
        alert.addButton(withTitle: T("Delete", "Apagar"))
        alert.addButton(withTitle: T("Cancel", "Cancelar"))
        let root = projectRoot
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.memoryAct(["delete-page", "--cwd", root, "--path", page.relative])
        }
    }

    private func decideProposal(_ proposal: MemoryProposal, approve: Bool) {
        memoryAct([approve ? "approve" : "reject", "--id", proposal.id])
    }

    /// memory.reindex: the wiki files edited on disk become a commit.
    func reindexMemory(root: String) {
        memoryAct(["reindex", "--cwd", root])
    }

    /// An action of the agent's CLI; refused, the reason in a sheet; done,
    /// the page read again.
    private func memoryAct(_ words: [String]) {
        // Said, not a beep: the command ran and nothing showed (the UX audit, 2026-11-18).
        guard settings.store.settings.memory.enabled else {
            return say(T("Project memory is off", "A memória do projeto está desligada"),
                       T("With it off there is no briefing: turn it on in the side column's Memory page.",
                         "Desligada, não há briefing: ligue na página Memória da coluna lateral."))
        }
        MemoryWiring.runAgent(words) { [weak self] code, answer in
            guard let self else { return }
            if code != 0 {
                let alert = NSAlert()
                alert.messageText = T("The memory agent refused", "O agente de memória recusou")
                alert.informativeText = answer["error"] as? String ?? ""
                alert.beginSheetModal(for: self.window)
            }
            self.refreshMemoryPage()
        }
    }

    /// memory.show-briefing: exactly what the next session here receives,
    /// in a read-only tab (this starts the engine, as the spec allows).
    private func showMemoryBriefing() {
        guard settings.store.settings.memory.enabled else { return NSSound.beep() }
        let root = projectRoot
        MemoryWiring.runAgentText(["briefing", "--cwd", root]) { [weak self] code, text in
            guard let self, let tabs = self.tabs else { return }
            guard code == 0 else {
                let alert = NSAlert()
                alert.messageText = T("The memory did not answer", "A memória não respondeu")
                // The client's `{"error":…}` in words: the raw JSON was on screen (2026-11-19).
                let reason = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])?["error"] as? String ?? text
                alert.informativeText = reason.contains("did not answer")
                    ? T("It may still be starting. Try again in a few seconds.", "Ela pode estar começando. Tente de novo em alguns segundos.")
                    : reason
                return alert.beginSheetModal(for: self.window)
            }
            if let open = tabs.document(identity: MemoryBriefingDocument.identity(for: root)) as? MemoryBriefingDocument {
                open.show(text)
                return tabs.open(open)
            }
            let document = MemoryBriefingDocument(root: root, briefing: text)
            let terminal = ThemeStore.shared.current.terminal
            document.paint(text: terminal.foreground.nsColor, background: terminal.background.nsColor)
            tabs.open(document, beside: self.settings.opensBeside)
        }
    }

    /// editor.save of a wiki page runs reindex for its project, so the
    /// owner's edit becomes a commit (docs/spec/memory.md: cada edição é um
    /// commit). The editor gives the app no save notice; the save command
    /// is the one way a page is saved from Cadex, so it is wrapped here.
    func withMemoryReindex(_ list: [Command]) -> [Command] {
        list.map { command in
            guard command.id == "editor.save", case .run(let save) = command.action else { return command }
            var wrapped = Command(id: command.id, title: command.title, keywords: command.keywords, category: command.category,
                                  defaultShortcut: command.defaultShortcut, action: .run { [weak self] in
                                      let document = self?.tabs?.activeDocument as? EditorDocument
                                      save()
                                      if let document, !document.hasUnsavedChanges { self?.wikiPageSaved(document.path) }
                                  }, unavailableReason: command.unavailableReason)
            wrapped.withArguments = command.withArguments
            wrapped.withArgumentsLater = command.withArgumentsLater
            wrapped.argumentHelp = command.argumentHelp
            return wrapped
        }
    }

    private func wikiPageSaved(_ path: String) {
        guard settings.store.settings.memory.enabled, path.hasSuffix(".md") else { return }
        let real = FileOpener.canonical(path)
        if let entry = MemoryProjects.entry(holding: real, folder: MemoryKit.folder()) ?? MemoryProjects.entry(holding: path, folder: MemoryKit.folder()) {
            return reindexMemory(root: entry.root)
        }
        if let wiki = memoryPage?.state?.wikiDir, real.hasPrefix(FileOpener.canonical(wiki) + "/") || path.hasPrefix(wiki + "/") {
            reindexMemory(root: projectRoot)
        }
    }
}
