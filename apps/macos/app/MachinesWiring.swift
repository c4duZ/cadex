import AppKit
import AgentTools
import Icons
import Menus
import Preview
import Machines
import SSH
import Strings
import UILooks
import StatusBar
import Terminal

/// The tailnet's machines in this window (docs/spec/machines.md, plan 23):
/// the Tailscale item of the status bar and its card, read only while they show, and
/// machines.connect's ssh tab.
extension WindowSession {
    /// The Tailscale item (its own since 2026-11-18; it was a group in the SSH card): "Tailnet
    /// 2/3", the machines read while it shows, and its card with each one (a click connects),
    /// pinged while the card is open.
    func makeTailscaleItem() -> StatusItem {
        let label = StatusLabel(icon: .globe, tip: "Tailscale")
        let item = StatusItem(id: "tailscale", title: "Tailscale",
                              subtitle: T("The machines of your tailnet: online, path, latency; a click connects",
                                          "As máquinas da sua tailnet: online, caminho, latência; o clique conecta"),
                              icon: .globe, side: .right, view: label)
        let show = { [weak label] in
            guard let label, let status = MachinesController.shared.status else { return }
            label.text = MachinesSection.titleText(status)
            label.dot = status.isRunning ? DesignTokens.Color.stateDone : DesignTokens.Color.textTertiary
        }
        var token: UUID?
        item.onVisible = { visible in
            if visible {
                token = MachinesController.shared.watch { show() }
                MachinesController.shared.refresh()
            } else if let id = token {
                MachinesController.shared.stop(id)
                token = nil
            }
        }
        let card = attachCard(to: label) { [weak self] close in
            let section = MachinesSection.make(width: UILooks.pt(StatusCard.width), text: DesignTokens.Color.textPrimary,
                                               secondary: DesignTokens.Color.textMuted) { machine in
                close()
                self?.connectMachine(machine, askUser: false)
            } ?? NSTextField(labelWithString: T("Tailscale is not running on this Mac", "O Tailscale não está rodando neste Mac"))
            let foot = StatusCard.build([.actions([
                .init(T("Share a port…", "Compartilhar uma porta…")) { [weak self] in _ = self?.commands.run("machines.share-port") },
                .init(T("Ping again", "Medir de novo")) { MachinesController.shared.pingOnline() },
            ])], close: close)
            let stack = NSStackView(views: [section, foot])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 6
            return stack
        }
        var cardToken: UUID?
        card.onOpenChange = { [weak card] open in
            if open {
                cardToken = MachinesController.shared.watch { card?.refresh() }
                MachinesController.shared.pingOnline()
            } else if let id = cardToken {
                MachinesController.shared.stop(id)
                cardToken = nil
            }
        }
        return item
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
        tabs.activeTerminal?.typeWhenReady("ssh \(quoted)\n")
    }
}

/// For the whole app: a terminal's `http://ubuntu-dev:3000` is offered in
/// the preview only when it names a machine of the tailnet (plan 23).
extension AppDelegate {
    func startMachines() {
        TerminalView.isOwnHost = { host, answer in MachinesController.shared.isMachine(host, then: answer) }
        // A device of the owner reaching this Mac through the tailnet speaks
        // the app socket's protocol (plan 23, phase F).
        TailnetListener.shared.onAccepted = { AgentToolsServer.shared.serveRemote($0) }
    }
}

/// Sharing the focused preview's local server (plan 23, phase G): the
/// commands, the preview bar's button (it runs machines.share-port by id),
/// the confirmation for the internet and the address shown with copy/open.
extension WindowSession {
    func shareActions() -> ShareActions {
        ShareActions(focusedLocalPort: { [weak self] in
            TailscaleServe.localPort(of: (self?.tabs?.activeDocument as? PreviewDocument)?.currentURL)
        }, confirmPublic: { [weak self] port, then in
            self?.confirm(T("Share localhost:\(port) on the internet?", "Compartilhar localhost:\(port) na internet?"),
                          T("Anyone with the address can open it, not only your devices, until you stop it (Funnel, a Tailscale beta).",
                            "Qualquer pessoa com o endereço abre, não só os seus aparelhos, até você parar (Funnel, um beta do Tailscale)."),
                          button: T("Share Publicly", "Compartilhar em público"), then: then)
        }, shared: { [weak self] url in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = T("Shared", "Compartilhado")
            alert.informativeText = url + "\n\n" + T("\"Stop Sharing a Preview\" in ⌘K turns it off.", "\"Parar de compartilhar um preview\" no ⌘K desliga.")
            alert.addButton(withTitle: T("Copy", "Copiar"))
            alert.addButton(withTitle: T("Open", "Abrir"))
            alert.addButton(withTitle: T("Done", "Pronto"))
            alert.beginSheetModal(for: self.window) { response in
                if response == .alertFirstButtonReturn {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                }
                if response == .alertSecondButtonReturn, let link = URL(string: url) { NSWorkspace.shared.open(link) }
            }
        }, failed: { [weak self] message in
            self?.say(T("Not shared", "Não compartilhado"), message)
        })
    }
}

extension AppDelegate {
    /// The preview bar's sharing button, while machines.tailscale is on: a
    /// menu with the three commands (share on the tailnet, on the internet,
    /// stop), each run by id; the ones that cannot run now are greyed.
    func startPreviewSharing() {
        PreviewDocument.extraBarItems = { document in
            guard MachinesController.shared.isEnabled else { return [] }
            let button = NSButton(image: Icon.globe.image(size: 14), target: nil, action: nil)
            button.isBordered = false
            button.toolTip = T("Share on Tailnet…", "Compartilhar na tailnet…")
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            let target = ClosureTarget { [weak document, weak button] in
                guard let document, let button else { return }
                let run = { (id: String) in _ = document.runCommand?(id) }
                let shares = !TailnetShares.shared.all.isEmpty
                PopupMenu.show([
                    MenuEntry(T("Share on Tailnet", "Compartilhar na tailnet"), icon: .globe) { run("machines.share-port") },
                    MenuEntry(T("Share Publicly…", "Compartilhar em público…"), icon: .globe,
                              isEnabled: MachinesController.shared.status?.funnelAllowed == true) { run("machines.share-public") },
                    MenuEntry(T("Stop Sharing…", "Parar de compartilhar…"), icon: .x, isEnabled: shares) { run("machines.stop-sharing") },
                ], below: button)
            }
            button.target = target
            button.action = #selector(ClosureTarget.fire)
            objc_setAssociatedObject(button, &ClosureTarget.key, target, .OBJC_ASSOCIATION_RETAIN)
            return [button]
        }
    }
}

/// A button's target that runs a closure (kept alive by the button).
final class ClosureTarget: NSObject {
    nonisolated(unsafe) static var key = 0
    let block: () -> Void
    init(_ block: @escaping () -> Void) { self.block = block }
    @objc func fire() { block() }
}
