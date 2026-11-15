import CommandPalette
import Foundation
import Icons
import Strings

/// What the app does for the tasks' commands: the asking and the tabs.
public struct WorktreesActions {
    public var newTask: @MainActor () -> Void
    public var open: @MainActor (TaskWorktree) -> Void
    public var remove: @MainActor (TaskWorktree) -> Void
    public var comment: @MainActor (TaskWorktree) -> Void
    public var editSetupHooks: @MainActor () -> Void
    /// The window's repository, or nil.
    public var repository: @MainActor () -> String?

    public init(newTask: @escaping @MainActor () -> Void, open: @escaping @MainActor (TaskWorktree) -> Void,
                remove: @escaping @MainActor (TaskWorktree) -> Void, comment: @escaping @MainActor (TaskWorktree) -> Void,
                editSetupHooks: @escaping @MainActor () -> Void, repository: @escaping @MainActor () -> String?) {
        self.newTask = newTask
        self.open = open
        self.remove = remove
        self.comment = comment
        self.editSetupHooks = editSetupHooks
        self.repository = repository
    }
}

/// The tasks' commands (ADR 0005; docs/spec/worktrees.md). The ones that
/// act on a task list the window's repository's tasks in ⌘K.
public enum WorktreesCommands {
    @MainActor
    public static func commands(palette: CommandPaletteController, actions: WorktreesActions) -> [Command] {
        let controller = WorktreesController.shared
        func pick(_ placeholder: String, _ act: @escaping @MainActor (TaskWorktree) -> Void) -> Command.Action {
            .run {
                palette.open(TaskSource(placeholder: placeholder, tasks: {
                    actions.repository().map { controller.tasks(repo: $0).map(\.worktree) } ?? []
                }, choose: act))
            }
        }
        return [
            Command(id: "worktrees.new-task", title: T("New Task", "Nova tarefa"),
                    keywords: ["task", "worktree", "branch", "agent", "tarefa", "nova"], category: .terminal,
                    action: .run { actions.newTask() }),
            Command(id: "worktrees.open", title: T("Open Task…", "Abrir tarefa…"),
                    keywords: ["task", "worktree", "open", "tarefa", "abrir"], category: .terminal,
                    action: pick(T("The task to open", "A tarefa a abrir"), actions.open)),
            Command(id: "worktrees.remove", title: T("Remove Task…", "Remover tarefa…"),
                    keywords: ["task", "worktree", "remove", "delete", "tarefa", "remover"], category: .terminal,
                    action: pick(T("The task to remove", "A tarefa a remover"), actions.remove)),
            Command(id: "worktrees.set-status", title: T("Set Task Status…", "Mudar o status da tarefa…"),
                    keywords: ["task", "status", "review", "done", "tarefa", "status", "pronto"], category: .terminal,
                    action: pick(T("The task", "A tarefa")) { task in
                        palette.open(StatusSource(task: task))
                    })
                .accepting("status=<todo|doing|review|done>") { request in
                    guard let status = request["status"].flatMap(TaskStatus.init(rawValue:)) else { return .failed("status is one of todo, doing, review, done") }
                    guard let task = taskOf(request.folder) else { return .failed("this terminal is not in a task (New Task makes one)") }
                    WorktreesController.shared.setStatus(status, of: task)
                    return .ok("the task is \(status.rawValue)")
                },
            Command(id: "worktrees.set-comment", title: T("Comment on a Task…", "Comentar uma tarefa…"),
                    keywords: ["task", "comment", "note", "tarefa", "comentário"], category: .terminal,
                    action: pick(T("The task to comment on", "A tarefa a comentar"), actions.comment))
                .accepting("comment=<a few words>") { request in
                    guard let comment = request["comment"]?.trimmingCharacters(in: .whitespacesAndNewlines) else { return .failed("comment=<text> is needed") }
                    guard let task = taskOf(request.folder) else { return .failed("this terminal is not in a task (New Task makes one)") }
                    WorktreesController.shared.setComment(String(comment.prefix(200)), of: task)
                    return .ok(comment.isEmpty ? "the comment is cleared" : "commented")
                },
            Command(id: "worktrees.edit-setup-hooks", title: T("Edit Task Setup Hooks…", "Editar os hooks de preparo das tarefas…"),
                    keywords: ["setup", "hooks", "install", "worktree", "preparo", "hooks"], category: .terminal,
                    action: .run { actions.editSetupHooks() }),
        ]
    }
}

/// The task worktree holding `folder` (the agent's terminal), nil when it is
/// the repository itself or no repository: the agent's status goes only to a
/// task (plan 20 phase B).
@MainActor
func taskOf(_ folder: String) -> String? {
    guard let root = WorktreesCore.repository(of: folder), let main = WorktreesCore.list(repo: root).first, main.path != root else { return nil }
    return root
}

/// ⌘K's list of the repository's tasks.
@MainActor
final class TaskSource: PaletteSource {
    let placeholder: String
    var emptyText: String { T("No tasks in this repository", "Nenhuma tarefa neste repositório") }
    var icon: Icon { .gitBranch }
    private let tasks: () -> [TaskWorktree]
    private let pick: (TaskWorktree) -> Void

    init(placeholder: String, tasks: @escaping () -> [TaskWorktree], choose: @escaping (TaskWorktree) -> Void) {
        self.placeholder = placeholder
        self.tasks = tasks
        self.pick = choose
    }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        let store = WorktreesController.shared.store
        show(tasks().filter { query.isEmpty || $0.branch.localizedCaseInsensitiveContains(query) }.map { task in
            PaletteItem(id: task.path, title: task.branch.isEmpty ? (task.path as NSString).lastPathComponent : task.branch,
                        detail: store.task(task.path)?.status.title, icon: .gitBranch)
        }, nil)
    }

    func choose(_ item: PaletteItem) {
        if let task = tasks().first(where: { $0.path == item.id }) { pick(task) }
    }

    func stop() {}
}

/// ⌘K's list of statuses for one task.
@MainActor
final class StatusSource: PaletteSource {
    let task: TaskWorktree
    init(task: TaskWorktree) { self.task = task }
    var placeholder: String { T("The status of \(task.branch)", "O status de \(task.branch)") }
    var emptyText: String { "" }
    var icon: Icon { .check }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        let now = WorktreesController.shared.store.task(task.path)?.status
        show(TaskStatus.allCases.map { PaletteItem(id: $0.rawValue, title: $0.title, detail: $0 == now ? T("now", "agora") : nil, icon: .check) }, nil)
    }

    func choose(_ item: PaletteItem) {
        if let status = TaskStatus(rawValue: item.id) { WorktreesController.shared.setStatus(status, of: task.path) }
    }

    func stop() {}
}
