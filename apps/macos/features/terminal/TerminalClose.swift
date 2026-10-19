import AppKit

/// Closing a terminal with a program running in the foreground (a server,
/// an agent, `sleep 100`) asks first (docs/spec/terminal.md, "Fechar e
/// restaurar"). The alert's "não perguntar de novo" turns it off.
extension TerminalView {
    static let confirmCloseKey = "terminal.confirmClose"

    /// True when the view can close right away. Otherwise shows a sheet and
    /// returns false; `close` runs if the user confirms, `cancel` if not.
    public func shouldClose(then close: @escaping @MainActor () -> Void,
                            cancelled cancel: @escaping @MainActor () -> Void = {}) -> Bool {
        let asks = UserDefaults.standard.object(forKey: Self.confirmCloseKey) as? Bool ?? true
        guard asks, session?.hasForegroundProcess == true, let window else { return true }

        let alert = NSAlert()
        alert.messageText = "Fechar o terminal com um programa rodando?"
        alert.informativeText = "O programa em primeiro plano vai ser encerrado."
        alert.addButton(withTitle: "Fechar")
        // NSAlert gives Esc only to a button titled "Cancel" in English.
        alert.addButton(withTitle: "Cancelar").keyEquivalent = "\u{1B}"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Não perguntar de novo"
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                if alert.suppressionButton?.state == .on {
                    UserDefaults.standard.set(false, forKey: Self.confirmCloseKey)
                }
                response == .alertFirstButtonReturn ? close() : cancel()
            }
        }
        return false
    }
}
