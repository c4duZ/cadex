import Foundation
import Strings

/// What the Changes tab lists (docs/spec/inspector.md, Changes; plan 26 phase C2): what the agent
/// changed in its last turn, all of the task against where it started, or what has no commit.
public enum ChangesScope: String, CaseIterable, Sendable {
    case lastTurn, task, uncommitted

    public var title: String {
        switch self {
        case .lastTurn: T("Last turn", "Última rodada")
        case .task: T("Task", "Tarefa")
        case .uncommitted: T("Uncommitted", "Sem commit")
        }
    }
}

/// One changed file as the tab draws it (components.inspector.fileRow): the letter, the name and
/// its folder, the lines added and removed; with today's status entry when the file has
/// uncommitted changes, so stage, discard and the diff keep working on it.
struct ChangesRow: Equatable {
    let file: GitRepository.ReviewFile
    let entry: GitRepository.Entry?

    /// M amber, A green as the mockup; a new file git does not know shows as A; a conflict, U
    /// (the diff against HEAD calls it M: review of 2026-11-17).
    var letter: Character {
        if entry?.kind == .conflict { return "U" }
        return file.status == "?" ? "A" : file.status
    }

    /// "staged" or "partly staged" for a file with changes in the index.
    var stagedNote: String? {
        guard let entry, entry.isStaged else { return nil }
        return entry.isUnstaged ? T("partly staged", "parte no stage") : T("staged", "no stage")
    }
    var name: String { (file.path as NSString).lastPathComponent }
    var folder: String {
        let dir = (file.path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }

    /// Each list shows at most this many (docs/spec/inspector.md, many changes).
    static let limit = 500

    /// The rows of a scope from the files against its base: the last turn keeps only what the
    /// agent edited (relative paths); the entries come from the status, by path.
    static func rows(_ files: [GitRepository.ReviewFile], entries: [GitRepository.Entry], keep: Set<String>?) -> [ChangesRow] {
        let byPath = Dictionary(entries.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        return files.filter { keep?.contains($0.path) ?? true }.prefix(limit).map { ChangesRow(file: $0, entry: byPath[$0.path]) }
    }
}
