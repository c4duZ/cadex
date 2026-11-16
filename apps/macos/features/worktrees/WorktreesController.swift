import Foundation
import Strings

/// What "New Task" will do, shown before anything is made (docs/spec/worktrees.md).
public struct TaskPlan: Equatable, Sendable {
    public let repo: String
    public let name: String
    public let branch: String
    /// Where it starts: the repository's branch now, kept for the review.
    public let base: String
    /// The folder of the repository's tasks, and this task's folder in it.
    public let root: String
    public let path: String
    /// The root is outside the authorized folders: the owner says yes once.
    public let needsAuthorization: Bool
    /// The repository's setup hooks, and whether the owner has not seen them yet.
    public let hooks: [String]
    public let hooksNeedConfirmation: Bool
    /// First task of the repository: say that Claude Code's folder trust, if it
    /// asks, is accepted once for the repository and all its tasks.
    public let explainTrust: Bool
}

/// A task made: where, and what `.worktreeinclude` gave it.
public struct TaskMade: Equatable, Sendable {
    public let path: String
    public let copied: Int
    public let unmatched: [String]
}

/// The tasks of each repository and what Cadex knows of them, for the
/// whole app (docs/spec/worktrees.md, plan 19 phase D). Making and taking
/// away go through the core; the asking, the tabs and the agent are the app's.
@MainActor
public final class WorktreesController {
    public static let shared = WorktreesController()

    public var store = WorktreesStore()
    /// worktrees.root: empty is beside each repository, `<repo>.worktrees`.
    public var rootSetting = ""
    /// worktrees.setupHooks: repository → the commands, in order.
    public var setupHooks: [String: [String]] = [:]
    /// Runs "Run on"'s scripts on other machines (tests: a fake ssh).
    public var remoteRunner = RemoteTaskRunner()
    private var watchers: [UUID: () -> Void] = [:]

    init() {}

    public func watch(_ changed: @escaping () -> Void) -> UUID {
        let id = UUID()
        watchers[id] = changed
        changed()
        return id
    }

    public func stop(_ id: UUID) { watchers[id] = nil }

    public func publish() {
        for changed in watchers.values { changed() }
    }

    /// The folder a repository's tasks go in.
    public func tasksRoot(of repo: String) -> String {
        rootSetting.isEmpty ? repo + ".worktrees" : (rootSetting as NSString).expandingTildeInPath + "/" + (repo as NSString).lastPathComponent
    }

    /// The repository's task worktrees (the main one left out), with their notes.
    public func tasks(repo: String) -> [(worktree: TaskWorktree, info: TaskInfo?)] {
        WorktreesCore.list(repo: repo).dropFirst().map { ($0, store.task($0.path)) }
    }

    /// "In Progress · fixing the header", for Agents' group of that folder.
    public func note(for folder: String) -> String? {
        guard let info = store.task(folder) else { return nil }
        return [info.status.title, info.comment].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The plan for `name` in `repo`: a branch no worktree uses and a folder
    /// not taken ("-2", "-3"…), from the branch checked out now.
    public func plan(name: String, repo: String) -> TaskPlan {
        let base = WorktreesCore.branchName(name)
        let used = Set(WorktreesCore.list(repo: repo).map(\.branch))
        let root = tasksRoot(of: repo)
        var branch = base
        var n = 2
        while used.contains(branch) || FileManager.default.fileExists(atPath: root + "/" + branch) {
            branch = "\(base)-\(n)"
            n += 1
        }
        let hooks = setupHooks[repo] ?? []
        let info = store.repo(repo)
        return TaskPlan(repo: repo, name: name, branch: branch, base: WorktreesCore.currentBranch(repo), root: root,
                        path: root + "/" + branch, needsAuthorization: !WorktreesCore.isAuthorized(root),
                        hooks: hooks, hooksNeedConfirmation: !hooks.isEmpty && info.confirmedHooks != hooks,
                        explainTrust: !info.trustExplained)
    }

    /// Makes the plan's worktree once the owner said yes to what needed it:
    /// the folder (authorized), the branch and worktree, the files outside
    /// git, the task's note (in progress). Returns git's message on refusal.
    public func make(_ plan: TaskPlan) -> Result<TaskMade, TaskError> {
        try? FileManager.default.createDirectory(atPath: plan.root, withIntermediateDirectories: true)
        if plan.needsAuthorization, !WorktreesCore.authorize(plan.root) { return .failure(.git(T("The folder could not be authorized.", "Não deu para autorizar a pasta."))) }
        if let message = WorktreesCore.create(repo: plan.repo, path: plan.path, branch: plan.branch, base: plan.base.isEmpty ? "HEAD" : plan.base) {
            return .failure(.git(message))
        }
        let copied = WorktreesCore.copyIncludes(repo: plan.repo, worktree: plan.path)
        store.setTask(plan.path) { info in
            info.status = .doing
            info.base = plan.base
            info.created = Date()
        }
        if plan.hooksNeedConfirmation { store.setRepo(plan.repo) { $0.confirmedHooks = plan.hooks } }
        if plan.explainTrust { store.setRepo(plan.repo) { $0.trustExplained = true } }
        publish()
        return .success(TaskMade(path: plan.path, copied: copied.copied, unmatched: copied.unmatched))
    }

    /// What taking the task away would lose; empty: safe; nil: git failed.
    public func whatWouldBeLost(_ task: TaskWorktree) -> [String]? {
        WorktreesCore.whatWouldBeLost(path: task.path, branch: task.branch)
    }

    /// Takes it away (and its branch, when asked and merged); git's message on refusal.
    public func remove(_ task: TaskWorktree, repo: String, deleteBranch: Bool) -> String? {
        let refused = WorktreesCore.remove(repo: repo, path: task.path, branch: deleteBranch && !task.branch.isEmpty ? task.branch : nil)
        if refused == nil || !FileManager.default.fileExists(atPath: task.path) { store.forget(task.path) }
        publish()
        return refused
    }

    /// Told every status set, by whoever set it (the owner, the agent's
    /// cadex_worktree_status): the app's memory takes "review" as the
    /// task-ready milestone (plan 22 phase F).
    public var onStatusChange: (@MainActor (TaskStatus, String) -> Void)?

    public func setStatus(_ status: TaskStatus, of path: String) {
        store.setTask(path) { $0.status = status }
        publish()
        onStatusChange?(status, path)
    }

    public func setComment(_ comment: String, of path: String) {
        store.setTask(path) { $0.comment = comment }
        publish()
    }
}

public enum TaskError: Error, Equatable {
    case git(String)
}
