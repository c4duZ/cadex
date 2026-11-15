import CommandPalette
import Foundation
import Icons
import Strings

/// What the app does with a conversation of the history: the tab, the
/// clipboard, the Finder and the workspace are the app's.
public struct AgentHistoryActions {
    public var resume: @MainActor (AgentHistoryEntry) -> Void
    public var continueIn: @MainActor (AgentHistoryEntry) -> Void
    public var copyCommand: @MainActor (AgentHistoryEntry) -> Void
    public var reveal: @MainActor (AgentHistoryEntry) -> Void

    public init(resume: @escaping @MainActor (AgentHistoryEntry) -> Void, continueIn: @escaping @MainActor (AgentHistoryEntry) -> Void,
                copyCommand: @escaping @MainActor (AgentHistoryEntry) -> Void, reveal: @escaping @MainActor (AgentHistoryEntry) -> Void) {
        self.resume = resume
        self.continueIn = continueIn
        self.copyCommand = copyCommand
        self.reveal = reveal
    }
}

/// The history's commands (ADR 0005): from ⌘K each opens the list of
/// conversations, searched like the page, and acts on the chosen one; the
/// page's menu does the same on its row.
public enum AgentHistoryCommands {
    @MainActor
    public static func commands(palette: CommandPaletteController, actions: AgentHistoryActions,
                                accountName: @escaping @MainActor (String) -> String) -> [Command] {
        func pick(_ placeholder: String, _ act: @escaping @MainActor (AgentHistoryEntry) -> Void) -> Command.Action {
            .run { palette.open(AgentHistorySource(placeholder: placeholder, accountName: accountName, choose: act)) }
        }
        return [
            Command(id: "agents.resume-session", title: T("Resume Agent Conversation…", "Retomar conversa de agente…"),
                    keywords: ["resume", "history", "conversation", "claude", "retomar", "histórico", "conversa"], category: .terminal,
                    action: pick(T("The conversation to resume in its account", "A conversa a retomar na conta dela"), actions.resume)),
            Command(id: "agents.continue-in-account", title: T("Continue Agent Conversation in Another Account…", "Continuar conversa de agente em outra conta…"),
                    keywords: ["continue", "fork", "account", "limit", "continuar", "conta", "limite"], category: .terminal,
                    action: pick(T("The conversation to continue elsewhere", "A conversa a continuar em outra conta"), actions.continueIn)),
            Command(id: "agents.copy-resume-command", title: T("Copy Agent Conversation's Resume Command…", "Copiar o comando de retomar uma conversa…"),
                    keywords: ["copy", "resume", "command", "copiar", "retomar", "comando"], category: .terminal,
                    action: pick(T("The conversation whose command to copy", "A conversa cujo comando copiar"), actions.copyCommand)),
            Command(id: "agents.reveal-session-log", title: T("Reveal Agent Conversation's Log…", "Mostrar o arquivo de uma conversa…"),
                    keywords: ["reveal", "finder", "log", "jsonl", "mostrar", "arquivo"], category: .terminal,
                    action: pick(T("The conversation whose file to show", "A conversa cujo arquivo mostrar"), actions.reveal)),
        ]
    }
}

/// ⌘K's list of conversations: the newest first, the words matched in the
/// title, folder and branch at once and in what was said when the index
/// answers. Opening it brings the index up to the disk once (no watching).
@MainActor
final class AgentHistorySource: PaletteSource {
    let placeholder: String
    var emptyText: String { T("No conversation found", "Nenhuma conversa encontrada") }
    var icon: Icon { .clipboardText }
    private let accountName: (String) -> String
    private let pick: (AgentHistoryEntry) -> Void
    private var shown: [String: AgentHistoryEntry] = [:]
    private var watching: UUID?

    init(placeholder: String, accountName: @escaping (String) -> String, choose: @escaping (AgentHistoryEntry) -> Void) {
        self.placeholder = placeholder
        self.accountName = accountName
        self.pick = choose
    }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        let history = AgentHistoryController.shared
        if watching == nil { watching = history.watch { [weak self] in self?.search(query, show: show) } }
        let list = { (matches: Set<String>?) in
            let rows = AgentHistoryRows.make(history.entries, query: query, matches: matches, project: nil, grouping: .account,
                                             accountName: self.accountName)
            let entries = rows.compactMap { item -> AgentHistoryEntry? in if case .entry(let e) = item { return e } else { return nil } }
                .sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }.prefix(200)
            self.shown = Dictionary(entries.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
            show(entries.map { PaletteItem(id: $0.path, title: $0.title, detail: AgentHistoryRows.detail($0, accountName: self.accountName($0.account)),
                                           icon: .clipboardText) },
                 history.progress.map { T("indexing \($0.done)/\($0.total)", "indexando \($0.done)/\($0.total)") })
        }
        list(nil)
        if !query.trimmingCharacters(in: .whitespaces).isEmpty { history.search(query) { found in list(found) } }
    }

    func choose(_ item: PaletteItem) {
        if let entry = shown[item.id] { pick(entry) }
    }

    func stop() {
        if let watching { AgentHistoryController.shared.stop(watching) }
        watching = nil
    }
}
