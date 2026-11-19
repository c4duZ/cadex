import Agents
import AppKit
import Explorer
import Icons
import Memory
import Projects
import Strings
import UILooks

/// The project page's Sessions and Memory (plan 34 D and E; docs/design/projects/proposta.html):
/// the lines and, for the chosen one, the detail rendered from the memory's page (never the .md).
/// Sessions come from the history; their summary, tags and body from the memory's session page,
/// and what the memory kept from them from the pages whose source is that session.
extension WindowSession {
    func projectItems(_ folder: String, _ section: ProjectSection, query: String) -> [PageListItem] {
        let now = Date()
        switch section {
        case .sessions:
            return projectSessions(folder).prefix(80).map { entry in
                PageListItem(id: entry.id, title: entry.title, note: [Self.accountName(entry.account), Self.place(entry.cwd, folder), ProjectPageWords.when(entry.updated, now: now)]
                    .filter { !$0.isEmpty }.joined(separator: " · "), noteLogo: true)
            }
        case .memory:
            let pages = (projectMemory[folder] ?? []).filter { !$0.relative.hasPrefix("sessions/") }
                .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || ($0.summary ?? "").localizedCaseInsensitiveContains(query) }
            return pages.map { page in
                let (glyph, tint, group, _) = Self.memoryKind(page)
                let from = page.sessionID.flatMap { id in projectSessions(folder).first { $0.id == id }?.title }
                let note = [from.map { T("from \"\($0)\"", "de \"\($0)\"") }, ProjectPageWords.when(page.learnedAt ?? page.time, now: now)]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                return PageListItem(id: page.path, title: page.title, note: note, tile: glyph, tint: tint, group: group)
            }.sorted { Self.groupOrder($0.group) < Self.groupOrder($1.group) }
        default:
            return []
        }
    }

    func projectDetail(_ folder: String, _ section: ProjectSection, _ id: String) -> PageDetail? {
        switch section {
        case .sessions: sessionDetail(folder, id)
        case .memory: memoryDetail(folder, id)
        default: nil
        }
    }

    private func sessionDetail(_ folder: String, _ id: String) -> PageDetail? {
        guard let entry = projectSessions(folder).first(where: { $0.id == id }) else { return nil }
        let pages = projectMemory[folder] ?? []
        let page = pages.first { $0.relative.hasPrefix("sessions/") && $0.sessionID == id }
        let text = page.flatMap { try? String(contentsOfFile: $0.path, encoding: .utf8) } ?? ""
        var blocks: [PageDetail.Block] = page?.summary.map { [.paragraph($0)] } ?? []
        blocks += Self.blocks(text).filter { $0 != blocks.first }.prefix(24)
        let kept = pages.filter { !$0.relative.hasPrefix("sessions/") && $0.sessionID == id }.map { kept in
            let (glyph, tint, _, _) = Self.memoryKind(kept)
            return PageDetail.Related(tile: glyph, tint: tint, text: kept.title)
        }
        let when = entry.updated?.formatted(date: .abbreviated, time: .shortened) ?? ""
        let fold = settings.store.settings.memory.enabled ? Self.receivedFold(entry.id) : nil
        var buttons = [PageDetail.Button(T("Resume", "Retomar"), primary: true) { [weak self] in self?.historyActions().resume(entry) },
                       PageDetail.Button(T("Continue in Another Account…", "Continuar em outra conta…")) { [weak self] in self?.historyActions().continueIn(entry) }]
        if let page { buttons.append(PageDetail.Button(T("View the Page", "Ver a página")) { [weak self] in self?.openRendered(page.path) }) }
        return PageDetail(title: entry.title, meta: [Self.accountName(entry.account), Self.place(entry.cwd, folder), when].filter { !$0.isEmpty }.joined(separator: " · "),
                          metaLogo: true, blocks: blocks.isEmpty ? Self.historyBlocks(entry) : blocks,
                          tags: MemoryPageText.tags(text), relatedTitle: T("What the memory kept", "O que a memória guardou"), related: kept, buttons: buttons,
                          fold: fold)
    }

    /// What the session received at its start (plan 35 H): the briefing the engine kept for it, read
    /// from the memory's folder; a plain note when none was kept.
    private static func receivedFold(_ session: String) -> PageDetail.Fold {
        let title = T("What this session was given", "O que esta sessão recebeu")
        if let text = MemorySessions.received(session: session, folder: MemoryKit.folder()) {
            return PageDetail.Fold(title: title, text: text)
        }
        return PageDetail.Fold(title: title, text: T(
            "Nothing kept for this session: it started before Cadex kept briefings, more than 30 days ago, with an empty briefing, or without the memory.",
            "Nada guardado desta sessão: ela começou antes de o Cadex guardar o briefing, há mais de 30 dias, com o briefing vazio, ou sem a memória."), plain: true)
    }

    private func memoryDetail(_ folder: String, _ path: String) -> PageDetail? {
        guard let page = projectMemory[folder]?.first(where: { $0.path == path }) else { return nil }
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let (_, tint, _, chip) = Self.memoryKind(page)
        let session = page.sessionID.flatMap { id in projectSessions(folder).first { $0.id == id } }
        let age = ProjectPageWords.when(page.learnedAt ?? page.time, now: Date())
        let meta = [session.map { T("from \"\($0.title)\"", "de \"\($0.title)\"") }, session.map { Self.accountName($0.account) }, age.isEmpty ? nil : age]
            .compactMap { $0 }.joined(separator: " · ")
        var buttons = [PageDetail.Button(T("Edit", "Editar")) { [weak self] in
            WorkspaceFolder.allow((path as NSString).deletingLastPathComponent)
            self?.opener?.open(path)
        }]
        if let session { buttons.append(PageDetail.Button(T("Open the Session", "Abrir a sessão")) { [weak self] in self?.historyActions().resume(session) }) }
        buttons.append(PageDetail.Button(T("Delete…", "Apagar…"), danger: true) { [weak self] in self?.memoryPage?.onDelete?(page) })
        var blocks = Self.blocks(text)
        if blocks.isEmpty, let summary = page.summary { blocks = [.paragraph(summary)] }
        return PageDetail(chip: (chip, tint), title: page.title, meta: meta, metaLogo: session != nil, blocks: blocks, tags: MemoryPageText.tags(text), buttons: buttons)
    }

    /// A session the memory has no page of, told from the history itself (2026-11-18: most of
    /// bkdg-center's said only "no summary yet"): what was asked first, when and how long, where.
    private static func historyBlocks(_ entry: AgentHistoryEntry) -> [PageDetail.Block] {
        var blocks: [PageDetail.Block] = []
        let asked = entry.firstPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !asked.isEmpty {
            blocks += [.heading(T("What was asked", "O que foi pedido")), .paragraph(asked.count > 400 ? String(asked.prefix(400)) + "…" : asked)]
        }
        var when: [String] = []
        if let started = entry.started { when.append(T("started ", "começou ") + started.formatted(date: .abbreviated, time: .shortened)) }
        if let started = entry.started, let updated = entry.updated, updated > started {
            let minutes = Int(updated.timeIntervalSince(started) / 60)
            when.append(minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min")
        }
        if !entry.branch.isEmpty { when.append(T("branch ", "branch ") + entry.branch) }
        if !when.isEmpty { blocks += [.heading(T("When and where", "Quando e onde")), .paragraph(when.joined(separator: " · "))] }
        blocks.append(.paragraph(T("The memory has no summary of this session: what it kept shows here once it has one.",
                                   "A memória não tem um resumo desta sessão: o que ela guardar aparece aqui quando tiver.")))
        return blocks
    }

    /// The memory's markdown as the page's blocks.
    private static func blocks(_ text: String) -> [PageDetail.Block] {
        MemoryPageText.blocks(text).map { block in
            switch block {
            case .heading(let text): .heading(text)
            case .paragraph(let text): .paragraph(text)
            case .item(let text): .item(text)
            }
        }
    }

    /// A page's kind: its glyph, its color, its group in the list and its chip.
    static func memoryKind(_ page: MemoryPage) -> (Icon, NSColor, String, String) {
        if page.relative.hasPrefix("_rules/") {
            return (.pushPin, DesignTokens.Color.stateReview, T("Rules · what every agent gets", "Regras · o que todo agente recebe"), T("Rule", "Regra"))
        }
        switch (page.kind ?? (page.relative as NSString).pathComponents.first ?? "").lowercased() {
        case "decision", "decisions": return (.checkCircle, DesignTokens.Color.accentLink, T("Decisions", "Decisões"), T("Decision", "Decisão"))
        case "gotcha", "gotchas", "pitfall", "warning": return (.warning, DesignTokens.Color.stateNeeds, T("Cautions", "Cuidados"), T("Caution", "Cuidado"))
        case "pattern", "patterns", "convention", "procedure", "procedures": return (.puzzlePiece, DesignTokens.Color.stateReview, T("Patterns", "Padrões"), T("Pattern", "Padrão"))
        default: return (.lightbulb, DesignTokens.Color.textSecondary, T("Other", "Outras"), T("Note", "Nota"))
        }
    }

    private static func groupOrder(_ group: String?) -> Int {
        [T("Rules · what every agent gets", "Regras · o que todo agente recebe"), T("Decisions", "Decisões"), T("Cautions", "Cuidados"), T("Patterns", "Padrões")]
            .firstIndex(of: group ?? "") ?? 9
    }

    /// The project's conversations, newest first; the empty ones left out (plan 35 H: a panel
    /// opened and closed with no prompt is not a session of the project).
    func projectSessions(_ folder: String) -> [AgentHistoryEntry] {
        AgentHistoryController.shared.entries.filter { $0.hasPrompt && Self.belongs($0.cwd, to: folder) }
            .sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }
    }

    /// Where a session ran: its task, else its folder's name when not the project's.
    private static func place(_ cwd: String, _ folder: String) -> String {
        taskName(cwd, project: folder) ?? (cwd == folder ? "" : (cwd as NSString).lastPathComponent)
    }

    /// A memory page opened in the editor already rendered.
    private func openRendered(_ path: String) {
        WorkspaceFolder.allow((path as NSString).deletingLastPathComponent)
        markdown?.renderNext.insert(path)
        opener?.open(path)
    }
}
