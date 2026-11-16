import AppKit
import Machines
import StatusBar
import Strings

/// Docker through the tailnet in this window (docs/spec/machines.md, plan
/// 23 phase D; ADR 0032): a machine's context used by one tab, by typing
/// `export DOCKER_CONTEXT=…` in its shell (the terminal has no environment
/// per tab, and `docker context use` would move every terminal of the
/// owner); the focused tab's context in the status bar; a container's
/// shell in a tab and its ports in the preview.
extension WindowSession {
    func dockerActions() -> DockerActions {
        DockerActions(useContext: { [weak self] in self?.useDockerContext($0) },
                      openShell: { [weak self] machine, container in
                          self?.typeInNewTerminal(Docker.shellLine(context: Docker.contextName(machine), container: container.name))
                      },
                      openPort: { [weak self] machine, port in self?.openPreview("http://\(machine.address):\(port)") },
                      destination: { [weak self] in self?.sshDestination($0) ?? $0.address })
    }

    /// `user@pc.tail1234.ts.net`, the user machines.connect remembered, or
    /// the address alone (ssh's own default user).
    func sshDestination(_ machine: Machine) -> String {
        settings.store.settings.machines.users[machine.address].map { $0 + "@" + machine.address } ?? machine.address
    }

    /// The focused terminal when its shell is at the prompt, else a new tab:
    /// typing into a running program would be read by it.
    func useDockerContext(_ machine: Machine?) {
        let apply = { [weak self] in
            guard let self, let tabs = self.tabs else { return }
            if tabs.activeTerminal == nil || tabs.activeTerminal?.hasForegroundProcess == true { tabs.newTab() }
            guard let terminal = tabs.activeTerminal else { return }
            terminal.session?.write(Docker.exportLine(machine.map(Docker.contextName)) + "\n")
            self.dockerContexts[ObjectIdentifier(terminal)] = machine.map(Docker.contextName)
            self.showDockerContext()
        }
        guard let machine else { return apply() }
        Task { [weak self] in
            guard let self else { return }
            if let error = await Docker.ensureContext(machine, destination: self.sshDestination(machine)) {
                return self.say(T("No Docker context for \(machine.name)", "Sem contexto do Docker para \(machine.name)"), error)
            }
            apply()
        }
    }

    func makeDockerItem() -> StatusItem {
        let label = StatusLabel(icon: .stack, tip: T("This tab's Docker", "O Docker desta aba"))
        label.onClick = { [weak self] in _ = self?.commands.run("machines.docker-context") }
        let item = StatusItem(id: "docker", title: "Docker",
                              subtitle: T("The machine whose Docker the focused tab uses, when not this Mac's", "A máquina cujo Docker a aba com foco usa, quando não é o deste Mac"),
                              icon: .stack, side: .right, view: label)
        dockerLabel = label
        dockerItem = item
        item.onVisible = { [weak self] visible in if visible { self?.showDockerContext() } }
        return item
    }

    /// "docker: pc" for the focused tab; nothing when it uses this Mac's.
    func showDockerContext() {
        guard let label = dockerLabel else { return }
        let context = tabs?.activeTerminal.flatMap { dockerContexts[ObjectIdentifier($0)] }
        label.text = context.map { "docker: " + $0 } ?? ""
        label.isHidden = context == nil
    }

    private func typeInNewTerminal(_ line: String) {
        guard let tabs else { return }
        tabs.newTab()
        tabs.activeTerminal?.session?.write(line + "\n")
    }
}
