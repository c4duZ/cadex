import Agents
import AppKit
import Machines
import SSH
import Strings
import Worktrees

/// "Run on" another machine (docs/spec/worktrees.md; ADR 0031, the
/// minimum, plan 23 phase C): the machines a task can go to (the hosts of
/// ~/.ssh/config and the tailnet's online machines), the worktree made
/// there over ssh by the worktrees feature, then a tab with the hooks and
/// `claude` there; the remote task's shell and its removal; and the
/// sessions there read for Agents only while the page is watched.
extension WindowSession {
    /// Where a task can run: this Mac is the nil choice, not listed here.
    func runTargets() -> [RunTarget] {
        let ssh = SSHController.shared
        let hosts = ssh.hosts.isEmpty ? SSHConfig.hosts(at: NSHomeDirectory() + "/.ssh/config") : ssh.hosts
        var targets = hosts.map { RunTarget(label: $0.alias, destination: $0.alias) }
        let users = settings.store.settings.machines.users
        for machine in MachinesController.shared.status?.others ?? [] where machine.online {
            let user = users[machine.address].map { $0 + "@" } ?? ""
            targets.append(RunTarget(label: machine.name, destination: user + machine.address))
        }
        return targets
    }

    /// The name, and "Run on" with this Mac first. The tailnet's list is
    /// read once when the dialog opens, if nothing read it yet.
    func askTaskName(preset: RunTarget?, then: @escaping (String, RunTarget?) -> Void) {
        let show = { [weak self] in
            guard let self else { return }
            let targets = self.runTargets()
            let alert = NSAlert()
            alert.messageText = T("New task", "Nova tarefa")
            alert.informativeText = T("Its name becomes a branch and a worktree; the agent opens in it. On another machine, the worktree and the agent are there, with its own Claude login.",
                                      "O nome vira um branch e uma worktree; o agente abre nela. Em outra máquina, a worktree e o agente ficam lá, com o login do Claude de lá.")
            let field = NSTextField(string: "")
            field.placeholderString = T("Fix the login", "Corrigir o login")
            let where_ = NSPopUpButton(frame: .zero, pullsDown: false)
            where_.addItem(withTitle: T("This Mac", "Este Mac"))
            for target in targets { where_.addItem(withTitle: target.label) }
            if let preset, let index = targets.firstIndex(of: preset) { where_.selectItem(at: index + 1) }
            let label = NSTextField(labelWithString: T("Run on", "Rodar em"))
            let row = NSStackView(views: [label, where_])
            let box = NSStackView(views: [field, row])
            box.orientation = .vertical
            box.alignment = .leading
            box.frame = NSRect(x: 0, y: 0, width: 300, height: 58)
            field.widthAnchor.constraint(equalToConstant: 300).isActive = true
            alert.accessoryView = box
            alert.addButton(withTitle: T("OK", "OK"))
            alert.addButton(withTitle: T("Cancel", "Cancelar"))
            alert.window.initialFirstResponder = field
            alert.beginSheetModal(for: self.window) { response in
                guard response == .alertFirstButtonReturn else { return }
                let index = where_.indexOfSelectedItem
                then(field.stringValue.trimmingCharacters(in: .whitespaces), index > 0 ? targets[index - 1] : nil)
            }
        }
        if MachinesController.shared.isEnabled, MachinesController.shared.status == nil { MachinesController.shared.refresh(show) } else { show() }
    }

    /// Where the repository is on that machine (asked once, remembered),
    /// then the worktree made there; a missing repository offers a clone.
    func newRemoteTask(name: String, repo: String, target: RunTarget) {
        let store = WorktreesController.shared.store
        if let folder = store.remoteFolder(repo, on: target.destination) { return makeRemoteTask(name: name, repo: repo, target: target, folder: folder, clone: false) }
        let guess = "~/" + (repo as NSString).lastPathComponent
        ask(T("Where is \((repo as NSString).lastPathComponent) on \(target.label)?", "Onde fica \((repo as NSString).lastPathComponent) em \(target.label)?"),
            T("Its folder there; Cadex remembers it for this machine. If there is no repository, Cadex offers to clone it.",
              "A pasta dele lá; o Cadex lembra para esta máquina. Se não houver repositório, o Cadex oferece clonar."),
            placeholder: guess) { [weak self] typed in
            self?.makeRemoteTask(name: name, repo: repo, target: target, folder: typed.isEmpty ? guess : typed, clone: false)
        }
    }

    private func makeRemoteTask(name: String, repo: String, target: RunTarget, folder: String, clone: Bool) {
        Task { [weak self] in
            let result = await WorktreesController.shared.makeRemote(name: name, repo: repo, target: target, folder: folder, clone: clone)
            guard let self else { return }
            switch result {
            case .made(let path, let branch):
                AgentAttention.shared.note(.taskCreated, text: branch + " · " + target.label, project: (repo as NSString).lastPathComponent)
                if let recipe = self.recipe(of: repo) {
                    // The environment on that machine, through its Docker context (ADR 0032).
                    let key = WorktreesController.shared.remoteTasks(repo: repo).first { $0.path == path && $0.target == target }?.noteKey ?? path
                    return self.startEnvironment(recipe, repo: repo, branch: branch, key: key, worktree: path, remote: target, prefix: [])
                }
                let hooks = self.settings.store.settings.worktrees.setupHooks[SettingsBridge.tilde(repo)] ?? []
                self.typeInNewTab(RemoteTaskScript.sshLine(target, RemoteTaskScript.agent(path: path, hooks: hooks)))
            case .noRepo:
                guard let origin = WorktreesController.origin(of: repo) else {
                    return self.say(T("No repository at \(folder) on \(target.label)", "Nenhum repositório em \(folder) em \(target.label)"),
                                    T("And this repository has no origin to clone from. Clone it there, then try again.",
                                      "E este repositório não tem origin para clonar. Clone lá e tente de novo."))
                }
                self.confirm(T("Clone into \(folder) on \(target.label)?", "Clonar em \(folder) em \(target.label)?"),
                             T("There is no repository there. Cadex will run git clone \(origin) on \(target.label), with its own access to it.",
                               "Não há repositório lá. O Cadex vai rodar git clone \(origin) em \(target.label), com o acesso de lá."),
                             button: T("Clone", "Clonar")) { [weak self] in
                    self?.makeRemoteTask(name: name, repo: repo, target: target, folder: folder, clone: true)
                }
            case .needsLogin(let message):
                self.say(T("ssh needs you on \(target.label)", "O ssh precisa de você em \(target.label)"),
                         T("Connect once in a tab (it may ask a password or to trust the machine), then try again.\n\n",
                           "Conecte uma vez numa aba (pode pedir senha ou para confiar na máquina) e tente de novo.\n\n") + message)
            case .failed(let message):
                self.say(T("The task was not made on \(target.label)", "A tarefa não foi criada em \(target.label)"), message)
            }
        }
    }

    /// worktrees.open-remote-shell, and a click on a remote task.
    func openRemoteTask(_ task: RemoteTask) {
        typeInNewTab(RemoteTaskScript.sshLine(task.target, RemoteTaskScript.shell(path: task.path)))
    }

    func removeRemoteTask(_ task: RemoteTask) {
        guard let repo = repository else { return }
        confirm(T("Remove the task \(task.branch) on \(task.target.label)?", "Remover a tarefa \(task.branch) em \(task.target.label)?"),
                T("Its worktree goes from \(task.target.label); git refuses if it has changes. The branch stays there.",
                  "A worktree sai de \(task.target.label); o git recusa se ela tiver mudanças. O branch fica lá."),
                button: T("Remove", "Remover")) { [weak self] in
            self?.askDestroyWithTask(task.noteKey) { destroy in self?.finishRemoveRemote(task, repo: repo, destroy: destroy) }
        }
    }

    private func finishRemoveRemote(_ task: RemoteTask, repo: String, destroy: Bool) {
        let env = WorktreesController.shared.store.environment(task.noteKey)
        // Both at once: a container with the folder mounted does not keep
        // git from removing the worktree on Linux.
        if destroy, let env { runEnvironment(.destroy, env, key: task.noteKey) }
        Task { [weak self] in
            guard let refused = await WorktreesController.shared.removeRemote(task, repo: repo) else { return }
            let message: String
            switch refused {
            case .needsLogin(let text), .failed(let text): message = text
            default: message = ""
            }
            self?.say(T("The task was not removed", "A tarefa não foi removida"), message)
        }
    }

    /// A session on another machine, opened from Agents: its task's shell
    /// there, else a shell in its folder.
    func openRemoteAgent(_ session: AgentSession) {
        let destination = String(session.account.dir.dropFirst("ssh://".count))
        let tasks = repository.map(WorktreesController.shared.remoteTasks) ?? []
        if let task = tasks.first(where: { $0.target.destination == destination && session.cwd.hasPrefix($0.path) }) { return openRemoteTask(task) }
        typeInNewTab(RemoteTaskScript.sshLine(RunTarget(label: session.machine ?? destination, destination: destination), RemoteTaskScript.shell(path: session.cwd)))
    }

    private func typeInNewTab(_ line: String) {
        guard let tabs else { return }
        tabs.newTab()
        tabs.activeTerminal?.session?.write(line + "\n")
    }
}

/// The sessions on the machines tasks run on, for Agents, read with
/// `claude agents --json` over ssh (BatchMode: never a question) every
/// 30 s, and only while the Agents page is watched (ADR 0031; nothing is
/// read with nobody looking).
extension AppDelegate {
    func startRemoteAgents() {
        var timer: Timer?
        AgentsController.shared.onWatching = { watched in
            timer?.invalidate()
            timer = nil
            guard watched else { return AgentsController.shared.remote = [] }
            RemoteAgentsReader.read()
            let tick = Timer(timeInterval: 30, repeats: true) { _ in MainActor.assumeIsolated { RemoteAgentsReader.read() } }
            tick.tolerance = 5
            RunLoop.main.add(tick, forMode: .common)
            timer = tick
        }
    }
}

@MainActor
enum RemoteAgentsReader {
    static var reading = false

    static func read() {
        let targets = WorktreesController.shared.store.remoteTargets
        guard !reading, !targets.isEmpty else { return }
        reading = true
        let runner = WorktreesController.shared.remoteRunner
        Task {
            var found: [AgentSession] = []
            for target in targets {
                let result = await runner.run(target, #"exec "$SHELL" -l -c 'claude agents --json'"#)
                if result.status == 0 {
                    found += AgentBackground.parseRemote(Data(result.out.utf8), machine: target.label, destination: target.destination)
                }
            }
            reading = false
            AgentsController.shared.remote = found
        }
    }
}
