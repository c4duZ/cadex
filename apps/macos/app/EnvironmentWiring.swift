import AppKit
import Machines
import Strings
import Worktrees

/// A task's throwaway environment in this window (docs/spec/worktrees.md;
/// ADR 0032; plan 23 phase E): the repository's recipe brings a container
/// up where the task's worktree is (typed in a tab: the output in sight,
/// the sidecar's key from the owner's shell); suspending, resuming and
/// destroying run the owner's docker in the background. A hibernated agent
/// suspends its task's environment and its relaunch resumes it; opening the
/// task resumes it too; removing the task asks to destroy it (yes by default).
extension WindowSession {
    /// The recipe of `repo`, or nil; one that does not read is said once.
    func recipe(of repo: String) -> EnvironmentRecipe? {
        switch EnvironmentRecipe.load(repo: repo) {
        case .success(let recipe): return recipe
        case .failure(let error):
            say(T("The environment recipe does not read", "A receita do ambiente não lê"), EnvironmentRecipe.file + ": " + error.description)
            return nil
        case nil: return nil
        }
    }

    /// "Run on" starts on the recipe's machine, when it names one known.
    func recipeTarget(_ repo: String) -> RunTarget? {
        guard case .success(let recipe) = EnvironmentRecipe.load(repo: repo), !recipe.machine.isEmpty else { return nil }
        return runTargets().first { $0.label == recipe.machine }
    }

    /// worktrees.environment-*: `key` is a task's path here, or a remote
    /// task's note key.
    func environmentAction(_ action: EnvironmentAction, key: String) {
        guard let repo = repository else { return }
        let store = WorktreesController.shared.store
        let remote = WorktreesController.shared.remoteTasks(repo: repo).first { $0.noteKey == key }
        switch action {
        case .up:
            guard let recipe = recipe(of: repo) else { return }
            let branch = remote?.branch ?? WorktreesController.shared.tasks(repo: repo).first { $0.worktree.path == key }?.worktree.branch ?? "task"
            startEnvironment(recipe, repo: repo, branch: branch, key: key, worktree: remote?.path ?? key, remote: remote?.target, prefix: [])
        case .suspend, .resume, .destroy:
            guard let env = store.environment(key) else { return }
            if action == .destroy {
                return confirm(T("Destroy the environment?", "Destruir o ambiente?"),
                               T("Its containers (\(env.containers.joined(separator: ", "))) are removed. The worktree's files stay.",
                                 "Os contêineres (\(env.containers.joined(separator: ", "))) são removidos. Os arquivos da worktree ficam."),
                               button: T("Destroy", "Destruir")) { [weak self] in self?.runEnvironment(.destroy, env, key: key) }
            }
            runEnvironment(action, env, key: key)
        }
    }

    /// The tab that brings it up: `prefix` (the setup hooks) first, then the
    /// recipe's script. A remote task's machine gets its Docker context.
    func startEnvironment(_ recipe: EnvironmentRecipe, repo: String, branch: String, key: String, worktree: String, remote: RunTarget?, prefix: [String]) {
        Task { [weak self] in
            guard let self else { return }
            if let remote, let error = await Docker.ensureContext(name: remote.label, destination: remote.destination) {
                return self.say(T("No Docker context for \(remote.label)", "Sem contexto do Docker para \(remote.label)"), error)
            }
            let env = EnvironmentScript.environment(recipe: recipe, repo: repo, branch: branch, context: remote?.label)
            WorktreesController.shared.store.setEnvironment(env, for: key)
            WorktreesController.shared.publish()
            self.tabs?.newTab(cwd: remote == nil ? worktree : nil)
            let line = EnvironmentScript.upLine(recipe, env, worktree: worktree)
            self.tabs?.activeTerminal?.session?.write((prefix + [line]).joined(separator: " && ") + "\n")
        }
    }

    func runEnvironment(_ action: EnvironmentAction, _ env: TaskEnvironment, key: String) {
        guard let docker = Docker.binary() else { return say(T("Docker is not installed", "O Docker não está instalado"), Docker.notInstalled) }
        let args: [String]
        switch action {
        case .suspend: args = EnvironmentScript.suspend(env)
        case .resume: args = EnvironmentScript.resume(env)
        case .destroy: args = EnvironmentScript.destroy(env)
        case .up: return
        }
        Task { [weak self] in
            let result = await Docker.run(docker, args, timeout: 60)
            let store = WorktreesController.shared.store
            guard result.status == 0 else {
                return self?.say(T("docker did not \(action.rawValue) it", "O docker não conseguiu (\(action.rawValue))"), result.err) ?? ()
            }
            var changed = env
            changed.state = action == .suspend ? .suspended : .running
            store.setEnvironment(action == .destroy ? nil : changed, for: key)
            WorktreesController.shared.publish()
        }
    }

    /// The task holding `folder` has an environment in `state`: change it
    /// (hibernation suspends, a relaunch or opening the task resumes).
    func followEnvironment(of folder: String?, to action: EnvironmentAction) {
        guard let folder, let key = WorktreesController.shared.store.environmentKey(containing: folder),
              let env = WorktreesController.shared.store.environment(key) else { return }
        if action == .suspend, env.state == .running { runEnvironment(.suspend, env, key: key) }
        if action == .resume, env.state == .suspended { runEnvironment(.resume, env, key: key) }
    }

    /// Removing a task with an environment: also destroy it? (yes by default).
    func askDestroyWithTask(_ key: String, then: @escaping (Bool) -> Void) {
        guard let env = WorktreesController.shared.store.environment(key) else { return then(false) }
        let alert = NSAlert()
        alert.messageText = T("Also destroy its environment?", "Destruir também o ambiente dela?")
        alert.informativeText = env.containers.joined(separator: ", ")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = T("Destroy the containers", "Destruir os contêineres")
        alert.suppressionButton?.state = .on
        alert.addButton(withTitle: T("Continue", "Continuar"))
        alert.addButton(withTitle: T("Cancel", "Cancelar"))
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            then(alert.suppressionButton?.state == .on)
        }
    }
}
