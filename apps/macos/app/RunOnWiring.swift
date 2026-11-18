import Agents
import AppKit
import CommandPalette
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

    /// Where the repository is on that machine (asked once, remembered),
    /// then the worktree made there; a missing repository offers a clone.
    /// `prompt` and `model`: the owner's words and the model from the New Task sheet; the words go
    /// by ssh's stdin into a file there, never into the command (as a race's do).
    func newRemoteTask(name: String, repo: String, target: RunTarget, prompt: String = "", model: String = "") {
        let store = WorktreesController.shared.store
        if let folder = store.remoteFolder(repo, on: target.destination) { return makeRemoteTask(name: name, repo: repo, target: target, folder: folder, clone: false, prompt: prompt, model: model) }
        let guess = "~/" + (repo as NSString).lastPathComponent
        ask(T("Where is \((repo as NSString).lastPathComponent) on \(target.label)?", "Onde fica \((repo as NSString).lastPathComponent) em \(target.label)?"),
            T("Its folder there; Cadex remembers it for this machine. If there is no repository, Cadex offers to clone it.",
              "A pasta dele lá; o Cadex lembra para esta máquina. Se não houver repositório, o Cadex oferece clonar."),
            placeholder: guess) { [weak self] typed in
            self?.makeRemoteTask(name: name, repo: repo, target: target, folder: typed.isEmpty ? guess : typed, clone: false, prompt: prompt, model: model)
        }
    }

    private func makeRemoteTask(name: String, repo: String, target: RunTarget, folder: String, clone: Bool, prompt: String = "", model: String = "") {
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
                guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return self.typeInNewTab(RemoteTaskScript.sshLine(target, RemoteTaskScript.agent(path: path, hooks: hooks)))
                }
                switch await WorktreesController.shared.remoteRunner.uploadPrompt(target, prompt) {
                case .failure(let error):
                    self.say(T("The words did not reach \(target.label)", "O pedido não chegou a \(target.label)"), error.message)
                case .success(let file):
                    guard let script = RemoteTaskScript.agent(path: path, hooks: hooks, promptFile: file, model: model) else {
                        return self.say(T("The agent did not start", "O agente não começou"),
                                        T("The model's name is not one Cadex can pass.", "O nome do modelo não é um que o Cadex consiga passar."))
                    }
                    self.typeInNewTab(RemoteTaskScript.sshLine(target, script))
                }
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
                    self?.makeRemoteTask(name: name, repo: repo, target: target, folder: folder, clone: true, prompt: prompt, model: model)
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

    /// agents.mute-machine: this Mac, each ssh host and each tailnet
    /// machine, muted or not; choosing one switches it (agents.mutedMachines).
    func muteMachineCommand(palette: CommandPaletteController) -> Command {
        Command(id: "agents.mute-machine", title: T("Mute or Unmute a Machine's Agents…", "Silenciar ou não os agentes de uma máquina…"),
                keywords: ["mute", "silence", "notifications", "machine", "silenciar", "notificações", "máquina"], category: .terminal,
                action: .run { [weak self] in
                    palette.open(AgentChoiceSource(placeholder: T("The machine to mute or unmute", "A máquina a silenciar ou não"), empty: "", items: {
                        guard let self else { return [] }
                        let muted = Set(self.settings.store.settings.agents.mutedMachines)
                        let names = ["local"] + self.runTargets().map(\.label)
                        return names.map { name in
                            PaletteItem(id: name, title: name == "local" ? T("This Mac", "Este Mac") : name,
                                        detail: muted.contains(name) ? T("muted: choose to unmute", "silenciado: escolha para voltar") : T("notifies", "notifica"),
                                        icon: .bell)
                        }
                    }, choose: { [weak self] name in
                        self?.settings.store.update { s in
                            if s.agents.mutedMachines.contains(name) { s.agents.mutedMachines.removeAll { $0 == name } } else { s.agents.mutedMachines.append(name) }
                        }
                    }))
                })
    }

    private func typeInNewTab(_ line: String) {
        guard let tabs else { return }
        tabs.newTab()
        tabs.activeTerminal?.typeWhenReady(line + "\n")
    }
}

/// The sessions on the machines tasks run on, for the project's page, read
/// with `claude agents --json` over ssh (BatchMode: never a question) every
/// 30 s, and only while a project's page is open (ADR 0031; nothing is
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
