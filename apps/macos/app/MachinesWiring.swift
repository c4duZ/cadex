import AppKit
import Machines
import SSH
import Strings
import Terminal

/// The tailnet's machines in this window (docs/spec/machines.md, plan 23):
/// the "Tailnet" group under the hosts of the SSH card, read only while
/// the card is open, and machines.connect's ssh tab. The ssh feature only
/// gets a view and an open/close notice; it does not import machines.
extension WindowSession {
    func attachMachines(to strip: SSHStrip) {
        strip.extraContent = { [weak self, weak strip] width, text, secondary in
            MachinesSection.make(width: width, text: text, secondary: secondary) { machine in
                strip?.closeCard()
                self?.connectMachine(machine, askUser: false)
            }
        }
        strip.onTestAgain = { MachinesController.shared.pingOnline() }
        var token: UUID?
        strip.onCardOpen = { [weak strip] open in
            if open {
                token = MachinesController.shared.watch { strip?.refreshCard() }
            } else if let id = token {
                MachinesController.shared.stop(id)
                token = nil
            }
        }
    }

    /// machines.connect: a new tab typing `ssh '<user>@<machine>'`. The user
    /// is asked the first time on each machine (this Mac's user offered)
    /// and kept in machines.users; `askUser` (⌥↩) asks again.
    func connectMachine(_ machine: Machine, askUser: Bool) {
        let known = settings.store.settings.machines.users[machine.address]
        if let known, !askUser { return openMachineTab(machine, user: known) }
        let alert = NSAlert()
        alert.messageText = T("Connect to ", "Conectar a ") + machine.name
        alert.informativeText = T("The user ssh logs in as on \(machine.address). Cadex remembers it for this machine.",
                                  "O usuário com que o ssh entra em \(machine.address). O Cadex lembra dele para esta máquina.")
        let field = NSTextField(string: known ?? NSUserName())
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: T("Connect", "Conectar"))
        alert.addButton(withTitle: T("Cancel", "Cancelar"))
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            let user = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard response == .alertFirstButtonReturn, !user.isEmpty, let self else { return }
            self.settings.store.update { $0.machines.users[machine.address] = user }
            self.openMachineTab(machine, user: user)
        }
    }

    private func openMachineTab(_ machine: Machine, user: String) {
        guard let tabs else { return }
        tabs.newTab()
        let target = user + "@" + machine.address
        let quoted = "'" + target.replacingOccurrences(of: "'", with: "'\\''") + "'"
        tabs.activeTerminal?.session?.write("ssh \(quoted)\n")
    }
}

/// For the whole app: a terminal's `http://ubuntu-dev:3000` is offered in
/// the preview only when it names a machine of the tailnet (plan 23).
extension AppDelegate {
    func startMachines() {
        TerminalView.isOwnHost = { host, answer in MachinesController.shared.isMachine(host, then: answer) }
    }
}
