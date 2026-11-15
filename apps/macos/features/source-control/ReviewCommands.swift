import AppKit
import CommandPalette
import Icons
import Strings

/// The review tab's commands (docs/spec/review.md, ADR 0005), all
/// `git.review-*` in phase B2. j/k/n/p are plain keys that only work with
/// the review in focus: elsewhere the command is unavailable and the key
/// goes on to the terminal or the editor (as Esc does for the picker).
public enum ReviewCommands {
    @MainActor
    public static func all(active: @escaping @MainActor () -> ReviewDocument?, palette: CommandPaletteController,
                           open: @escaping @MainActor () -> Void, canOpen: @escaping @MainActor () -> String?,
                           compare: @escaping @MainActor (_ repo: String, _ a: String, _ b: String) -> Void,
                           repo: @escaping @MainActor () -> String?) -> [Command] {
        func needsReview() -> String? { active() == nil ? T("No review open", "Nenhuma revisão aberta") : nil }
        func needsFocus() -> String? { active()?.isFocused == true ? nil : T("The review is not in focus", "A revisão não está em foco") }
        func onReview(_ id: String, _ title: String, _ keywords: [String], _ body: @escaping @MainActor (ReviewDocument) -> Void) -> Command {
            Command(id: id, title: title, keywords: keywords + ["review", "revisão"], category: .view,
                    action: .run { if let review = active() { body(review) } }, unavailableReason: needsReview)
        }
        func key(_ id: String, _ title: String, _ shortcut: String, _ body: @escaping @MainActor (ReviewDocument) -> Void) -> Command {
            Command(id: id, title: title, keywords: ["review", "revisão", "next", "próximo"], category: .view, defaultShortcut: shortcut,
                    action: .run { if let review = active() { body(review) } }, unavailableReason: needsFocus)
        }
        return [
            Command(id: "git.review-open", title: T("Review Changes", "Revisar as mudanças"),
                    keywords: ["review", "diff", "worktree", "task", "revisar", "tarefa", "base"], category: .view,
                    action: .run { open() }, unavailableReason: canOpen),
            Command(id: "git.review-compare-worktrees", title: T("Compare Two Worktrees", "Comparar duas worktrees"),
                    keywords: ["compare", "branches", "tries", "comparar", "tentativas"], category: .view,
                    action: .run {
                        guard let root = repo() else { return }
                        pickRef(palette, root, T("First branch or worktree", "Primeira branch ou worktree")) { a in
                            // The palette just closed: the second list opens on the next turn.
                            DispatchQueue.main.async { MainActor.assumeIsolated {
                                pickRef(palette, root, T("Compare \(a) with", "Comparar \(a) com")) { b in compare(root, a, b) }
                            } }
                        }
                    }, unavailableReason: { repo() == nil ? T("No git repository open", "Nenhum repositório git aberto") : nil }),
            onReview("git.review-set-base", T("Set Review Base", "Trocar a base da revisão"), ["base", "commit", "branch"]) { review in
                pickRef(palette, review.request.repo, T("Base: a branch, or type a commit", "Base: uma branch, ou digite um commit")) { review.setBase($0) }
            },
            onReview("git.review-stage-hunk", T("Stage Change", "Stage da mudança"), ["stage", "hunk", "trecho"]) { $0.stageChange(unstage: false) },
            onReview("git.review-unstage-hunk", T("Unstage Change", "Tirar a mudança do stage"), ["unstage", "hunk", "trecho"]) { $0.stageChange(unstage: true) },
            onReview("git.review-stage-lines", T("Stage Marked Lines", "Stage das linhas marcadas"), ["stage", "lines", "linhas"]) { $0.stageMarked(unstage: false) },
            onReview("git.review-unstage-lines", T("Unstage Marked Lines", "Tirar as linhas marcadas do stage"), ["unstage", "lines", "linhas"]) { $0.stageMarked(unstage: true) },
            key("git.review-next-file", T("Next File in Review", "Próximo arquivo da revisão"), "j") { $0.nextFile() },
            key("git.review-prev-file", T("Previous File in Review", "Arquivo anterior da revisão"), "k") { $0.previousFile() },
            key("git.review-next-hunk", T("Next Change in Review", "Próxima mudança da revisão"), "n") { $0.nextChange() },
            key("git.review-prev-hunk", T("Previous Change in Review", "Mudança anterior da revisão"), "p") { $0.previousChange() },
            onReview("git.review-toggle-collapse", T("Show or Fold Unchanged Lines", "Mostrar ou recolher as linhas sem mudança"), ["collapse", "fold", "recolher"]) { $0.toggleCollapse() },
            onReview("git.review-toggle-wrap", T("Toggle Line Wrap in Review", "Quebrar as linhas da revisão"), ["wrap", "quebra"]) { $0.toggleWrap() },
            onReview("git.review-toggle-whitespace", T("Show Whitespace in Review", "Mostrar os espaços na revisão"), ["whitespace", "espaços"]) { $0.toggleWhitespace() },
        ]
    }

    /// A branch from the list, or whatever commit the owner types.
    @MainActor
    static func pickRef(_ palette: CommandPaletteController, _ root: String, _ prompt: String, then: @escaping @MainActor (String) -> Void) {
        let repo = GitRepository(root: root)
        let source = RefSource(prompt: prompt, then: then)
        palette.open(source)
        repo.queue.async {
            let names = repo.branches().map(\.name)
            DispatchQueue.main.async { MainActor.assumeIsolated { source.names = names } }
        }
    }
}

/// The palette's list of branches; a typed name or sha that is not on it
/// is offered as is.
@MainActor
final class RefSource: PaletteSource {
    let placeholder: String
    var emptyText: String { T("Type a branch or a commit", "Digite uma branch ou um commit") }
    var names: [String] = [] { didSet { refresh?() } }
    private let then: @MainActor (String) -> Void
    private var refresh: (() -> Void)?

    init(prompt: String, then: @escaping @MainActor (String) -> Void) {
        placeholder = prompt
        self.then = then
    }

    var icon: Icon { .gitBranch }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        let typed = query.trimmingCharacters(in: .whitespaces)
        refresh = { [weak self] in self?.search(query, show: show) }
        var items = names.filter { typed.isEmpty || $0.localizedCaseInsensitiveContains(typed) }.map { PaletteItem(id: $0, title: $0, icon: .gitBranch) }
        if !typed.isEmpty, !names.contains(typed), !typed.hasPrefix("-"), !typed.contains(" ") {
            items.insert(PaletteItem(id: typed, title: T("Use “\(typed)”", "Usar “\(typed)”"), icon: .gitCommit), at: 0)
        }
        show(items, nil)
    }

    func choose(_ item: PaletteItem) { then(item.id) }
    func stop() { refresh = nil }
}
