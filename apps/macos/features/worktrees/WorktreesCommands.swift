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
    /// "Run on" (plan 23): the machines a task can go to, New Task already
    /// on one, a remote task's shell and its removal. Set after init.
    public var targets: @MainActor () -> [RunTarget] = { [] }
    public var newTaskOn: @MainActor (RunTarget) -> Void = { _ in }
    public var openRemote: @MainActor (RemoteTask) -> Void = { _ in }
    public var removeRemote: @MainActor (RemoteTask) -> Void = { _ in }
    /// The throwaway environment (plan 23 phase E), by the task's note key:
    /// up (the repository has a recipe), suspend, resume, destroy.
    public var environment: @MainActor (EnvironmentAction, String) -> Void = { _, _ in }

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
                    action: .run {
                        palette.open(TaskSource(placeholder: T("The task to remove", "A tarefa a remover"), tasks: {
                            actions.repository().map { controller.tasks(repo: $0).map(\.worktree) } ?? []
                        }, choose: actions.remove, remote: { actions.repository().map(controller.remoteTasks) ?? [] }, chooseRemote: actions.removeRemote))
                    }),
            environmentCommand(.up, palette: palette, actions: actions),
            environmentCommand(.suspend, palette: palette, actions: actions),
            environmentCommand(.resume, palette: palette, actions: actions),
            environmentCommand(.destroy, palette: palette, actions: actions),
            Command(id: "worktrees.new-task-on", title: T("New Task on Another Machine…", "Nova tarefa em outra máquina…"),
                    keywords: ["task", "remote", "run on", "ssh", "tailnet", "pc", "tarefa", "remota", "rodar em"], category: .terminal,
                    action: .run { palette.open(TargetSource(targets: actions.targets, choose: actions.newTaskOn)) }),
            Command(id: "worktrees.open-remote-shell", title: T("Open a Remote Task's Shell…", "Abrir o shell de uma tarefa remota…"),
                    keywords: ["task", "remote", "ssh", "shell", "tarefa", "remota"], category: .terminal,
                    action: .run {
                        palette.open(TaskSource(placeholder: T("The remote task", "A tarefa remota"), tasks: { [] }, choose: { _ in },
                                                remote: { actions.repository().map(controller.remoteTasks) ?? [] }, chooseRemote: actions.openRemote))
                    },
                    unavailableReason: {
                        (actions.repository().map(controller.remoteTasks) ?? []).isEmpty ? T("No task of this repository runs on another machine", "Nenhuma tarefa deste repositório roda em outra máquina") : nil
                    }),
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

public enum EnvironmentAction: String, CaseIterable, Sendable {
    case up, suspend, resume, destroy
}

extension WorktreesCommands {
    /// worktrees.environment-up and the others: the window's repository's
    /// tasks that can take the action, local and remote, in ⌘K.
    @MainActor
    static func environmentCommand(_ action: EnvironmentAction, palette: CommandPaletteController, actions: WorktreesActions) -> Command {
        let controller = WorktreesController.shared
        // The ids written whole, so grep and the parity check find them.
        let titles: [EnvironmentAction: (id: String, en: String, pt: String)] = [
            .up: ("worktrees.environment-up", "Start a Task's Environment…", "Subir o ambiente de uma tarefa…"),
            .suspend: ("worktrees.environment-suspend", "Suspend a Task's Environment…", "Suspender o ambiente de uma tarefa…"),
            .resume: ("worktrees.environment-resume", "Resume a Task's Environment…", "Retomar o ambiente de uma tarefa…"),
            .destroy: ("worktrees.environment-destroy", "Destroy a Task's Environment…", "Destruir o ambiente de uma tarefa…"),
        ]
        let fits: @MainActor (String) -> Bool = { key in
            let env = controller.store.environment(key)
            switch action {
            case .up: return env == nil
            case .suspend: return env?.state == .running
            case .resume: return env?.state == .suspended
            case .destroy: return env != nil
            }
        }
        let title = titles[action]!
        return Command(id: title.id, title: T(title.en, title.pt),
                       keywords: ["environment", "container", "docker", "ambiente", "contêiner", action.rawValue], category: .terminal,
                       action: .run {
                           palette.open(TaskSource(placeholder: T(title.en, title.pt), tasks: {
                               (actions.repository().map { controller.tasks(repo: $0).map(\.worktree) } ?? []).filter { fits($0.path) }
                           }, choose: { actions.environment(action, $0.path) },
                           remote: { (actions.repository().map(controller.remoteTasks) ?? []).filter { fits($0.noteKey) } },
                           chooseRemote: { actions.environment(action, $0.noteKey) }))
                       },
                       unavailableReason: {
                           guard action == .up else { return nil }
                           guard let repo = actions.repository() else { return T("Open a repository first", "Abra um repositório antes") }
                           return EnvironmentRecipe.load(repo: repo) == nil ? T("This repository has no .cadex/environment.toml", "Este repositório não tem .cadex/environment.toml") : nil
                       })
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
    /// The tasks on other machines, listed after these with the machine's name.
    private let remote: () -> [RemoteTask]
    private let pickRemote: (RemoteTask) -> Void

    init(placeholder: String, tasks: @escaping () -> [TaskWorktree], choose: @escaping (TaskWorktree) -> Void,
         remote: @escaping () -> [RemoteTask] = { [] }, chooseRemote: @escaping (RemoteTask) -> Void = { _ in }) {
        self.placeholder = placeholder
        self.tasks = tasks
        self.pick = choose
        self.remote = remote
        self.pickRemote = chooseRemote
    }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        let store = WorktreesController.shared.store
        let here = tasks().filter { query.isEmpty || $0.branch.localizedCaseInsensitiveContains(query) }.map { task in
            PaletteItem(id: task.path, title: task.branch.isEmpty ? (task.path as NSString).lastPathComponent : task.branch,
                        detail: store.task(task.path)?.status.title, icon: .gitBranch)
        }
        let there = remote().filter { query.isEmpty || $0.branch.localizedCaseInsensitiveContains(query) || $0.target.label.localizedCaseInsensitiveContains(query) }.map { task in
            PaletteItem(id: task.noteKey, title: task.branch + " · " + task.target.label, detail: store.task(task.noteKey)?.status.title, icon: .globe)
        }
        show(here + there, nil)
    }

    func choose(_ item: PaletteItem) {
        if let task = tasks().first(where: { $0.path == item.id }) { return pick(task) }
        if let task = remote().first(where: { $0.noteKey == item.id }) { pickRemote(task) }
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

/// ⌘K's list of machines a task can run on (worktrees.new-task-on).
@MainActor
final class TargetSource: PaletteSource {
    private let targets: () -> [RunTarget]
    private let pick: (RunTarget) -> Void

    init(targets: @escaping () -> [RunTarget], choose: @escaping (RunTarget) -> Void) {
        self.targets = targets
        self.pick = choose
    }

    var placeholder: String { T("Run the new task on", "Rodar a nova tarefa em") }
    var emptyText: String { T("No other machine: hosts of ~/.ssh/config and tailnet machines show here", "Nenhuma outra máquina: os hosts do ~/.ssh/config e as máquinas da tailnet aparecem aqui") }
    var icon: Icon { .globe }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        show(targets().filter { query.isEmpty || $0.label.localizedCaseInsensitiveContains(query) }.map {
            PaletteItem(id: $0.destination, title: $0.label, detail: $0.destination == $0.label ? nil : $0.destination, icon: .globe)
        }, nil)
    }

    func choose(_ item: PaletteItem) {
        if let target = targets().first(where: { $0.destination == item.id }) { pick(target) }
    }

    func stop() {}
}
