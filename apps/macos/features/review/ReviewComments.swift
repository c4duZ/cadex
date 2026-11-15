import Foundation

/// One worktree's comments (docs/spec/review.md): add, edit, delete, place
/// again after the agent edits, the text sent to the agent, and the history
/// of what was sent. The app links it to the review tab; this feature
/// knows nothing of the tab.
@MainActor
public final class ReviewComments {
    public let store: ReviewCommentStore
    public private(set) var pending: [ReviewComment]
    public private(set) var sent: [ReviewCommentStore.Sent]
    /// The list changed (the tab draws the comments again).
    public var onChange: (() -> Void)?

    public init(store: ReviewCommentStore) {
        self.store = store
        let file = store.read()
        pending = file.pending
        sent = file.sent
    }

    public func add(_ comment: ReviewComment) {
        pending.append(comment)
        save()
    }

    public func edit(_ id: String, body: String) {
        guard let at = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[at].body = body
        save()
    }

    public func delete(_ id: String) {
        pending.removeAll { $0.id == id }
        save()
    }

    public func clear() {
        pending = []
        save()
    }

    public func comment(_ id: String) -> ReviewComment? { pending.first { $0.id == id } }

    /// Each comment where its excerpt is now: `text(path, old)` gives the
    /// file's lines on that side, nil when the file left the review.
    public func place(_ text: (String, Bool) -> [String]?) {
        let placed = pending.map { comment in
            text(comment.path, comment.old).map { comment.placed(in: $0) } ?? { var gone = comment; gone.stale = true; return gone }()
        }
        guard placed != pending else { return }
        pending = placed
        save()
    }

    /// The text for the agent, every pending comment in the order of the
    /// files (`order`), then of the lines; nil when there is none.
    public func message(worktree: String, order: [String]) -> String? {
        guard !pending.isEmpty else { return nil }
        return ReviewCommentText.message(worktree: worktree, comments: sorted(order))
    }

    /// The comments went (pasted or copied): they leave the list for the history.
    public func markSent(_ text: String) {
        sent.insert(ReviewCommentStore.Sent(date: Date(), text: text, comments: pending), at: 0)
        pending = []
        save()
    }

    public func sorted(_ order: [String]) -> [ReviewComment] {
        pending.sorted { a, b in
            let ia = order.firstIndex(of: a.path) ?? Int.max
            let ib = order.firstIndex(of: b.path) ?? Int.max
            return ia != ib ? ia < ib : (a.path != b.path ? a.path < b.path : a.start < b.start)
        }
    }

    private func save() {
        store.write(ReviewCommentStore.File(pending: pending, sent: sent))
        onChange?()
    }
}

/// What the agent reads (docs/spec/review.md, Enviar ao agente): one block
/// per comment with the file, the lines, the quoted excerpt and the words.
public enum ReviewCommentText {
    public static func message(worktree: String, comments: [ReviewComment]) -> String {
        var text = "Review comments on \(worktree) (\(comments.count)):\n"
        for (number, comment) in comments.enumerated() {
            let lines = comment.start == comment.end ? "line \(comment.start)" : "lines \(comment.start)-\(comment.end)"
            text += "\n\(number + 1). \(comment.path), \(lines)" + (comment.old ? " (removed lines)" : "") + (comment.stale ? " (no longer in the file)" : "") + ":\n"
            for line in comment.lines.prefix(30) { text += "   > \(line)\n" }
            if comment.lines.count > 30 { text += "   > …\n" }
            for line in comment.body.split(separator: "\n", omittingEmptySubsequences: false) { text += "   \(line)\n" }
        }
        return text
    }
}
