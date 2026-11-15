import AgentTools
import AppKit
import ComputerUse
import Settings
import Strings

/// Computer use in the app (docs/adr/0026-computer-use.md, plan 20 phase E):
/// the settings into the controller, the owner's yes or no for an app, and
/// turning it on explaining and opening System Settings' two permissions.
extension AppDelegate {
    func startComputerUse() {
        let controller = ComputerUseController.shared
        controller.onAllowed = { [weak self] apps in
            self?.settings.store.update { $0.computerUse.allowedApps = apps.sorted() }
        }
        controller.askOwner = { app, answer in
            // After this turn: the request's own call stack goes first.
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = T("Let the agent use \(app)?", "Deixar o agente usar o \(app)?")
                alert.informativeText = T("It reads \(app)'s window and clicks and types in it. Password fields stay out. Forget this later with “Forget Apps Allowed to Agents”.",
                                          "Ele lê a janela do \(app) e clica e digita nela. Campos de senha ficam de fora. Esqueça isso depois com “Esquecer os apps permitidos aos agentes”.")
                alert.addButton(withTitle: T("Allow", "Permitir"))
                alert.addButton(withTitle: T("Don't Allow", "Não permitir"))
                NSApp.activate(ignoringOtherApps: true)
                answer(alert.runModal() == .alertFirstButtonReturn)
            }
        }
        controller.runCommand = { [weak self] id in self?.sessions.first?.commands.run(id) ?? false }
        // As it was at launch, with no question; a later turn-on explains.
        let now = settings.store.settings.computerUse
        controller.isEnabled = now.enabled
        applyComputerUse(now)
        settings.onComputerUse = { [weak self] in self?.applyComputerUse($0) }
    }

    /// Settings changed: the controller follows; turning on explains and
    /// opens the permissions (asked only then).
    func applyComputerUse(_ settings: Settings.ComputerUse) {
        let controller = ComputerUseController.shared
        let turnedOn = settings.enabled && !controller.isEnabled
        controller.isEnabled = settings.enabled
        controller.rules.allowed = Set(settings.allowedApps)
        controller.rules.blocked = Set(settings.blockedApps)
        if !settings.enabled { controller.stop() }
        if turnedOn { explainComputerUse() }
    }

    func explainComputerUse() {
        let alert = NSAlert()
        alert.messageText = T("Computer use needs two permissions", "O computer use precisa de duas permissões")
        alert.informativeText = T("In System Settings › Privacy & Security, turn Cadex on in Accessibility (to read and operate other apps) and in Screen Recording (for pictures of one window). Each app still asks you the first time.",
                                  "Em Ajustes do Sistema › Privacidade e Segurança, ligue o Cadex em Acessibilidade (para ler e operar outros apps) e em Gravação de Tela (para o print de uma janela). Cada app ainda pede a você na primeira vez.")
        alert.addButton(withTitle: T("Open System Settings", "Abrir os Ajustes do Sistema"))
        alert.addButton(withTitle: T("Later", "Depois"))
        if alert.runModal() == .alertFirstButtonReturn { openComputerUsePermissions() }
    }

    /// computer-use.open-permissions: the two panes; asking the system
    /// also lists Cadex there, ready to switch on.
    func openComputerUsePermissions() {
        // kAXTrustedCheckOptionPrompt's value, written out: the constant is a
        // global var Swift 6 will not read from here.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
}
