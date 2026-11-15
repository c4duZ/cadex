import AppKit
import CommandPalette
import Menus
import Review
import SourceControl
import Strings
import Tabs
import Worktrees

/// The review's comments in this window (docs/spec/review.md, plan 21
/// phase D): the review feature keeps them per worktree, the source-control
/// tab draws them as annotations under their lines; this links the two.
/// After each read the comments are placed again; the "+" of the margin
/// and `c` open the editor; a click on one offers Edit and Delete; Send
/// pastes them, without Enter, into the agent of that worktree, else copies.
@MainActor
enum ReviewCommentsHub {
    /// One list per worktree, shared by the windows.
    static var lists: [String: ReviewComments] = [:]
    /// A stale comment waiting for its new lines (the next c), by worktree.
    static var moving: [String: String] = [:]

    static func comments(for repo: String) -> ReviewComments {
        if let list = lists[repo] { return list }
        let main = WorktreesCore.list(repo: repo).first?.path ?? repo
        let list = ReviewComments(store: ReviewCommentStore(repo: (main as NSString).lastPathComponent, worktree: (repo as NSString).lastPathComponent))
        lists[repo] = list
        return list
    }
}

extension WindowSession {
    func attachComments(to review: ReviewDocument) {
        guard review.request.to == nil else { return }
        let list = ReviewCommentsHub.comments(for: review.request.repo)
        review.onLoaded = { [weak self, weak review] in if let review { self?.drawComments(on: review) } }
        list.onChange = { [weak self] in
            for case let open as ReviewDocument in self?.tabs?.allDocuments ?? [] where open.request.repo == review.request.repo { self?.drawComments(on: open) }
        }
        review.onCommentRequest = { [weak self, weak review] selection in if let review { self?.writeComment(on: review, selection) } }
        review.onAnnotation = { [weak self, weak review] id in
            guard let self, let review, let anchor = review.anchor else { return }
            var entries = [MenuEntry(T("Edit Comment", "Editar o comentário"), icon: .pencilSimple) { [weak self] in _ = self?.commands.run("review.edit-comment") },
                           MenuEntry(T("Delete Comment", "Apagar o comentário"), icon: .trash) { [weak self] in _ = self?.commands.run("review.delete-comment") }]
            // A stale one waits to be moved: mark the new lines, then this.
            if list.comment(id)?.stale == true {
                entries.insert(MenuEntry(T("Move to Marked Lines", "Mover para as linhas marcadas"), icon: .arrowRight) { [weak review] in
                    review?.announce(T("Mark the lines, then press c to move the comment there", "Marque as linhas e aperte c para mover o comentário para lá"))
                    ReviewCommentsHub.moving[review?.request.repo ?? ""] = id
                }, at: 0)
            }
            PopupMenu.show(entries, at: NSPoint(x: anchor.rect.midX, y: anchor.rect.maxY), in: anchor.view)
        }
        drawComments(on: review)
    }

    /// Placed where their lines are now, then drawn; the bar's button counts them.
    func drawComments(on review: ReviewDocument) {
        let list = ReviewCommentsHub.comments(for: review.request.repo)
        list.place { path, old in review.texts(of: path).map { old ? $0.before : $0.after } }
        review.annotations = list.pending.map { c in
            let text = c.stale ? T("Outdated — it was on:", "Desatualizado — estava em:") + "\n" + c.lines.prefix(6).map { "> " + $0 }.joined(separator: "\n") + "\n\n" + c.body : c.body
            return ReviewAnnotation(id: c.id, path: c.path, old: c.old, line: c.end, title: c.title, text: text, stale: c.stale)
        }
        review.barAction = list.pending.isEmpty ? nil : (T("Send to Agent (\(list.pending.count))", "Enviar ao agente (\(list.pending.count))"),
                                                       { [weak self] in _ = self?.commands.run("review.send-comments") })
    }

    private func writeComment(on review: ReviewDocument, _ selection: ReviewLineSelection, editing: ReviewComment? = nil) {
        guard let anchor = review.anchor else { return }
        let list = ReviewCommentsHub.comments(for: review.request.repo)
        let title = editing?.title ?? ReviewComment(path: selection.path, old: selection.old, start: selection.start, end: selection.end,
                                                    lines: [], before: [], after: [], body: "").title
        ReviewCommentEditor.show(at: anchor.rect, of: anchor.view, title: title, text: editing?.body ?? "") { body in
            if let editing { return list.edit(editing.id, body: body) }
            list.add(ReviewComment(path: selection.path, old: selection.old, start: selection.start, end: selection.end,
                                   lines: selection.lines, before: selection.before, after: selection.after, body: body))
        }
    }

    func registerReviewComments(palette: CommandPaletteController) {
        func review() -> ReviewDocument? { tabs?.activeDocument as? ReviewDocument }
        func list() -> ReviewComments? { review().flatMap { $0.request.to == nil ? ReviewCommentsHub.comments(for: $0.request.repo) : nil } }
        commands.register(ReviewCommentCommands.all(.init(
            add: { [weak self] in
                guard let review = review(), let selection = review.markedSelection() else { return }
                let repo = review.request.repo
                // Moving a stale comment: its words go to these lines.
                if let id = ReviewCommentsHub.moving.removeValue(forKey: repo) {
                    return ReviewCommentsHub.comments(for: repo).move(id, to: ReviewComment(
                        path: selection.path, old: selection.old, start: selection.start, end: selection.end,
                        lines: selection.lines, before: selection.before, after: selection.after, body: ""))
                }
                self?.writeComment(on: review, selection)
            },
            edit: { [weak self] in
                guard let review = review(), let id = review.cursorAnnotation, let comment = list()?.comment(id) else { return }
                let selection = ReviewLineSelection(path: comment.path, old: comment.old, start: comment.start, end: comment.end, lines: [], before: [], after: [])
                self?.writeComment(on: review, selection, editing: comment)
            },
            delete: { if let id = review()?.cursorAnnotation { list()?.delete(id) } },
            send: { [weak self] in if let review = review() { self?.sendComments(of: review) } },
            clear: { [weak self] in self?.confirmClearComments() },
            showSent: { palette.open(SentCommentsSource(sent: list()?.sent ?? [])) },
            canAdd: { review()?.isFocused == true && list() != nil ? nil : T("The review is not in focus", "A revisão não está em foco") },
            canEdit: { review()?.cursorAnnotation == nil ? T("Put the cursor on a comment", "Ponha o cursor num comentário") : nil },
            canSend: { (list()?.pending.isEmpty ?? true) ? T("No comment to send", "Nenhum comentário para enviar") : nil },
            canShowSent: { (list()?.sent.isEmpty ?? true) ? T("Nothing sent yet", "Nada enviado ainda") : nil })))
    }

    /// Pasted into the agent of that worktree (no Enter: the owner reads and
    /// presses it), else copied; either way they go to the history.
    private func sendComments(of review: ReviewDocument) {
        let repo = review.request.repo
        let list = ReviewCommentsHub.comments(for: repo)
        guard let text = list.message(worktree: (repo as NSString).lastPathComponent, order: review.paths) else { return }
        let agents = (tabs?.agentTerminals ?? []).filter { ($0.currentDirectory ?? "").hasPrefix(repo) }
        if let terminal = agents.first(where: { $0.pasteFromApp(text, images: []) }) {
            list.markSent(text)
            tabs?.focus(terminal)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        list.markSent(text)
        review.announce(T("Copied — no agent of this task takes a paste", "Copiado — nenhum agente desta tarefa aceita colagem"))
    }

    private func confirmClearComments() {
        guard let review = tabs?.activeDocument as? ReviewDocument else { return }
        let alert = NSAlert()
        alert.messageText = T("Delete the comments not sent?", "Apagar os comentários não enviados?")
        alert.addButton(withTitle: T("Delete", "Apagar"))
        alert.addButton(withTitle: T("Cancel", "Cancelar"))
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { ReviewCommentsHub.comments(for: review.request.repo).clear() }
        }
    }
}
