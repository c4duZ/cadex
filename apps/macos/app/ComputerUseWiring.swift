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
                alert.informativeText = T("It reads \(app)'s window and clicks and types in it. Password fields stay out. Cadex remembers a yes until you press Stop or use “Forget Apps Allowed to Agents”; a no asks again next time.",
                                          "Ele lê a janela do \(app) e clica e digita nela. Campos de senha ficam de fora. O Cadex lembra o sim até você apertar Parar ou usar “Esquecer os apps permitidos aos agentes”; um não pergunta de novo na próxima vez.")
                // The safe answer is the default (Return); allowing takes a
                // click: the owner allowed by reflex on the blue button (2026-11-15).
                alert.addButton(withTitle: T("Don't Allow", "Não permitir"))
                let allow = alert.addButton(withTitle: T("Always Allow", "Permitir sempre"))
                allow.keyEquivalent = ""
                NSApp.activate(ignoringOtherApps: true)
                // A sheet on the window, not runModal: a modal alert stopped the main queue, so every
                // session's requests and hooks (the preview too) went unanswered until the owner saw
                // the alert behind another window (2026-11-20, "Cadex is not running").
                guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) else {
                    return answer(alert.runModal() == .alertSecondButtonReturn)
                }
                window.makeKeyAndOrderFront(nil)
                alert.beginSheetModal(for: window) { response in answer(response == .alertSecondButtonReturn) }
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
        alert.informativeText = T("In System Settings › Privacy & Security, turn Cadex on where macOS lets apps control the computer (Accessibility; Device Control and Data Access on newer macOS), to read and operate other apps, and in Screen & System Audio Recording, for pictures of one window. Each app still asks you the first time.",
                                  "Em Ajustes do Sistema › Privacidade e Segurança, ligue o Cadex onde o macOS deixa apps controlarem o computador (Acessibilidade; Controle do Dispositivo e Acesso a Dados nos macOS novos), para ler e operar outros apps, e em Gravação de Tela e Áudio do Sistema, para o print de uma janela. Cada app ainda pede a você na primeira vez.")
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
        // Privacy & Security itself, not a pane inside: newer macOS has no
        // Privacy_Accessibility pane, the permission moved (the owner, 2026-11-15).
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") { NSWorkspace.shared.open(url) }
    }
}
