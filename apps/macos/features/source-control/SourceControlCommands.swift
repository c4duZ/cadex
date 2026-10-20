import AppKit
import CommandPalette
import Strings

/// The source-control commands (ADR 0005). Buttons, the lists' menu and
/// ⌘Enter in the message run these ids.
public enum SourceControlCommands {
    @MainActor
    public static func all(_ git: SourceControlController, palette: CommandPaletteController,
                           activeDiff: @escaping @MainActor () -> DiffDocument? = { nil }) -> [Command] {
        func needsRepo() -> String? { git.repo == nil ? T("No git repository open", "Nenhum repositório git aberto") : nil }
        func needsSelection() -> String? { git.panel.selectedEntries().isEmpty ? T("No file selected", "Nenhum arquivo selecionado") : nil }
        func selected() -> [GitRepository.Entry] { git.panel.selectedEntries().map(\.0) }
        return [
            Command(id: "git.commit", title: T("Commit", "Fazer o commit"), keywords: ["commit", "git"], category: .file,
                    action: .run { git.commit() }, unavailableReason: needsRepo),
            Command(id: "git.stage-all", title: T("Stage All Changes", "Stage de todas as mudanças"), keywords: ["git add", "stage"], category: .file,
                    action: .run { git.stageAll() }, unavailableReason: needsRepo),
            Command(id: "git.unstage-all", title: T("Unstage All", "Unstage de tudo"), keywords: ["git reset", "unstage"], category: .file,
                    action: .run { git.unstageAll() }, unavailableReason: needsRepo),
            Command(id: "git.stage", title: T("Stage File", "Stage do arquivo"), keywords: ["git add"], category: .file,
                    action: .run { git.stage(selected()) }, unavailableReason: needsSelection),
            Command(id: "git.unstage", title: T("Unstage File", "Unstage do arquivo"), keywords: ["git reset"], category: .file,
                    action: .run { git.unstage(selected()) }, unavailableReason: needsSelection),
            Command(id: "git.discard", title: T("Discard File Changes", "Descartar as mudanças do arquivo"), keywords: ["git restore", "undo", "desfazer"],
                    category: .file, action: .run { git.discard(selected()) }, unavailableReason: needsSelection),
        ] + opening(git, needsSelection: needsSelection) + [
            Command(id: "git.reveal", title: T("Reveal Changed File in Finder", "Revelar o arquivo alterado no Finder"), keywords: ["finder", "show", "mostrar"],
                    category: .file, action: .run { git.reveal(selected()) }, unavailableReason: needsSelection),
            Command(id: "git.fetch", title: T("Git Fetch", "Git fetch"), keywords: ["remote", "buscar", "remoto"], category: .file,
                    action: .run { git.fetch() }, unavailableReason: needsRepo),
            Command(id: "git.pull", title: T("Git Pull (Fast-Forward Only)", "Git pull (só fast-forward)"), keywords: ["update", "puxar", "atualizar"], category: .file,
                    action: .run { git.pull() }, unavailableReason: needsRepo),
            Command(id: "git.push", title: T("Git Push", "Git push"), keywords: ["publish", "enviar", "publicar"], category: .file,
                    action: .run { git.push() }, unavailableReason: needsRepo),
            Command(id: "git.refresh", title: T("Refresh Git Status", "Atualizar o status do git"), keywords: ["status", "refresh"], category: .file,
                    action: .run { git.refresh() }, unavailableReason: needsRepo),
            Command(id: "diff.toggle-layout", title: T("Toggle Side-by-Side/Unified Diff", "Alternar diff lado a lado/unificado"), keywords: ["diff", "patch", "unified"],
                    category: .view, action: .run { activeDiff()?.toggleLayout() },
                    unavailableReason: { activeDiff() == nil ? T("No diff open", "Nenhum diff aberto") : nil }),
            Command(id: "git.switch-branch", title: T("Switch Branch", "Trocar de branch"), keywords: ["checkout", "switch", "branch"], category: .file,
                    action: .run { palette.open(BranchSource(git: git)) }, unavailableReason: needsRepo),
        ]
    }
}

extension SourceControlCommands {
    /// The diff and the file, each where the setting says, beside or in a
    /// new tab: wherever something opens, both ways are offered (owner,
    /// 2026-10-20).
    @MainActor
    static func opening(_ git: SourceControlController, needsSelection: @escaping @MainActor () -> String?) -> [Command] {
        func entry() -> (GitRepository.Entry, Bool)? { git.panel.selectedEntries().first }
        let diffs: [(String, String, Bool?)] = [
            ("git.open-diff", T("Open File Diff", "Ver o diff do arquivo"), nil), ("git.open-diff-beside", T("Open Diff Beside", "Ver o diff ao lado"), true),
            ("git.open-diff-in-tab", T("Open Diff in New Tab", "Ver o diff em nova aba"), false),
        ]
        let files: [(String, String, Bool?)] = [
            ("git.open-file", T("Open Changed File", "Abrir o arquivo alterado"), nil), ("git.open-file-beside", T("Open File Beside", "Abrir o arquivo ao lado"), true),
            ("git.open-file-in-tab", T("Open File in New Tab", "Abrir o arquivo em nova aba"), false),
        ]
        return diffs.map { id, title, beside in
            Command(id: id, title: title, keywords: ["diff"], category: .file,
                    action: .run { if let (e, staged) = entry() { git.openDiff(e, staged: staged, beside: beside) } },
                    unavailableReason: needsSelection)
        } + files.map { id, title, beside in
            Command(id: id, title: title, keywords: ["open", "abrir"], category: .file,
                    action: .run { if let (e, _) = entry() { git.openFile(e, beside: beside) } }, unavailableReason: needsSelection)
        }
    }
}

/// The branches in the palette; choosing one switches to it (a remote one
/// becomes a local branch tracking it).
@MainActor
final class BranchSource: PaletteSource {
    private weak var git: SourceControlController?
    private var branches: [(name: String, remote: Bool)] = []

    init(git: SourceControlController) {
        self.git = git
    }

    var placeholder: String { T("Switch to branch", "Trocar para a branch") }
    var emptyText: String { T("No branches", "Nenhuma branch") }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        guard let repo = git?.repo else { return show([], nil) }
        if branches.isEmpty {
            show([], T("Loading…", "Carregando…"))
            repo.queue.async {
                let list = repo.branches()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self.branches = list
                        self.search(query, show: show)
                    }
                }
            }
            return
        }
        let current = git?.status.branch ?? ""
        let items = branches
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .map { PaletteItem(id: ($0.remote ? "remote\t" : "local\t") + $0.name, title: $0.name,
                               detail: $0.name == current ? T("current", "atual") : ($0.remote ? T("remote", "remota") : nil)) }
        show(items, nil)
    }

    func choose(_ item: PaletteItem) {
        let parts = item.id.split(separator: "\t", maxSplits: 1)
        guard parts.count == 2 else { return }
        let name = String(parts[1])
        let remote = parts[0] == "remote"
        git?.perform { $0.switchTo(name, remote: remote) }
    }

    func stop() {}
}
