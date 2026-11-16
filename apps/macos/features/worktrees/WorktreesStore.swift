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
        /// Plan 23: the tasks on other machines, by this Mac's repository,
        /// and where each repository is on each machine (destination → folder).
        var remote: [String: [RemoteTask]] = [:]
        var remoteFolders: [String: [String: String]] = [:]
        /// The tasks' throwaway environments, by the task's note key.
        var environments: [String: TaskEnvironment] = [:]

        init() {}

        // Every field may be missing: a file from before a field existed
        // must still read whole (a strict decode would drop every note).
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            tasks = try c.decodeIfPresent([String: TaskInfo].self, forKey: .tasks) ?? [:]
            repos = try c.decodeIfPresent([String: RepoInfo].self, forKey: .repos) ?? [:]
            remote = (try? c.decodeIfPresent([String: [RemoteTask]].self, forKey: .remote)) ?? [:]
            remoteFolders = (try? c.decodeIfPresent([String: [String: String]].self, forKey: .remoteFolders)) ?? [:]
            environments = (try? c.decodeIfPresent([String: TaskEnvironment].self, forKey: .environments)) ?? [:]
        }
    }

    let path: String
    private(set) var file = File()

    /// CADEX_WORKTREES_FILE: a test instance's own notes, never the owner's
    /// (plan 24 phase C: a race tested in the app wrote them until then).
    public static var defaultPath: String {
        if let file = ProcessInfo.processInfo.environment["CADEX_WORKTREES_FILE"], !file.isEmpty { return file }
        return FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Application Support/Cadex/worktrees.json"
    }

    public init(path: String = WorktreesStore.defaultPath) {
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

    public func remoteTasks(_ repo: String) -> [RemoteTask] { file.remote[repo] ?? [] }

    public func addRemote(_ task: RemoteTask, repo: String) {
        file.remote[repo, default: []].append(task)
        save()
    }

    public func forgetRemote(_ task: RemoteTask, repo: String) {
        file.remote[repo]?.removeAll { $0.path == task.path && $0.target == task.target }
        file.tasks[task.noteKey] = nil
        save()
    }

    /// Where `repo` is on the machine `destination`, once the owner said.
    public func remoteFolder(_ repo: String, on destination: String) -> String? { file.remoteFolders[repo]?[destination] }

    public func setRemoteFolder(_ folder: String, repo: String, on destination: String) {
        file.remoteFolders[repo, default: [:]][destination] = folder
        save()
    }

    /// Every machine some task of any repository runs on: Agents asks them.
    public var remoteTargets: [RunTarget] {
        var seen: [RunTarget] = []
        for task in file.remote.values.flatMap({ $0 }) where !seen.contains(task.target) { seen.append(task.target) }
        return seen
    }

    public func environment(_ key: String) -> TaskEnvironment? { file.environments[key] }

    /// The local task whose worktree holds `folder`, when it has an
    /// environment (a terminal's folder → its task's environment).
    public func environmentKey(containing folder: String) -> String? {
        file.environments.keys.filter { $0.hasPrefix("/") && (folder == $0 || folder.hasPrefix($0 + "/")) }.max { $0.count < $1.count }
    }

    public func setEnvironment(_ environment: TaskEnvironment?, for key: String) {
        file.environments[key] = environment
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
