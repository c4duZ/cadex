import Foundation
import Strings

/// Where a task stands (docs/spec/worktrees.md, Status e comentário).
public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case todo, doing, review, done

    public var title: String {
        switch self {
        case .todo: T("To Do", "A fazer")
        case .doing: T("In Progress", "Em andamento")
        case .review: T("In Review", "Em revisão")
        case .done: T("Done", "Pronto")
        }
    }
}

/// What Cadex keeps of a task, never in git: its status, a short comment
/// on what it does now, the branch it started from (for the review of plan
/// 21) and when it was made.
public struct TaskInfo: Codable, Equatable, Sendable {
    public var status: TaskStatus = .todo
    public var comment = ""
    public var base = ""
    public var created = Date()
}

/// Per repository: the setup hooks the owner already saw, and whether the
/// folder-trust note was shown.
public struct RepoInfo: Codable, Equatable, Sendable {
    public var confirmedHooks: [String] = []
    public var trustExplained = false
}

/// The tasks' and repositories' notes in one JSON file in Cadex's folder
/// (`…/Cadex/worktrees.json`), written whole at each change.
@MainActor
public final class WorktreesStore {
    struct File: Codable {
        var tasks: [String: TaskInfo] = [:]
        var repos: [String: RepoInfo] = [:]
    }

    let path: String
    private(set) var file = File()

    public init(path: String = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Application Support/Cadex/worktrees.json") {
        self.path = path
        if let data = FileManager.default.contents(atPath: path), let read = try? JSONDecoder().decode(File.self, from: data) { file = read }
    }

    public func task(_ path: String) -> TaskInfo? { file.tasks[path] }
    public func repo(_ path: String) -> RepoInfo { file.repos[path] ?? RepoInfo() }

    public func setTask(_ path: String, _ change: (inout TaskInfo) -> Void) {
        var info = file.tasks[path] ?? TaskInfo()
        change(&info)
        file.tasks[path] = info
        save()
    }

    public func setRepo(_ path: String, _ change: (inout RepoInfo) -> Void) {
        var info = file.repos[path] ?? RepoInfo()
        change(&info)
        file.repos[path] = info
        save()
    }

    /// A task that left: its note goes too.
    public func forget(_ path: String) {
        file.tasks[path] = nil
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
