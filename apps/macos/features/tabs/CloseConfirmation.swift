import AppKit
import Terminal

/// Asks before closing panes with a program in the foreground (a server,
/// an agent, `sleep 100`): docs/spec/tabs.md, "Fechar". The alert's "não
/// perguntar de novo" turns it off (TerminalPreferences.confirmClose).
@MainActor
enum CloseConfirmation {
    /// Runs `close` now if nothing is running or the user turned the
    /// question off; otherwise asks in a sheet and runs it on "Fechar".
    static func confirm(running: Bool, in window: NSWindow?, what: String,
                        then close: @escaping @MainActor () -> Void, cancelled: @escaping @MainActor () -> Void = {}) {
        let asks = TerminalPreferences.current.confirmClose
        guard asks, running, let window else {
            close()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Fechar \(what) com um programa rodando?"
        alert.informativeText = "O programa em primeiro plano vai ser encerrado."
        alert.addButton(withTitle: "Fechar")
        // NSAlert gives Esc only to a button titled "Cancel" in English.
        alert.addButton(withTitle: "Cancelar").keyEquivalent = "\u{1B}"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Não perguntar de novo"
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                if alert.suppressionButton?.state == .on {
                    TerminalPreferences.current.confirmClose = false
                }
                response == .alertFirstButtonReturn ? close() : cancelled()
            }
        }
    }

    /// Closing the window or quitting with documents not saved.
    static func confirmUnsaved(count: Int, in window: NSWindow?,
                               then close: @escaping @MainActor () -> Void, cancelled: @escaping @MainActor () -> Void) {
        guard let window else {
            close()
            return
        }
        let alert = NSAlert()
        alert.messageText = count == 1 ? "Fechar com 1 arquivo não salvo?" : "Fechar com \(count) arquivos não salvos?"
        alert.informativeText = "As mudanças não salvas serão perdidas."
        alert.addButton(withTitle: "Fechar sem salvar")
        alert.addButton(withTitle: "Cancelar").keyEquivalent = "\u{1B}"
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated { response == .alertFirstButtonReturn ? close() : cancelled() }
        }
    }
}
