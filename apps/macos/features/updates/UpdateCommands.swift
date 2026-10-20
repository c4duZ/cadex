import CommandPalette
import Strings

/// The updates commands (ADR 0005): the title bar's button and the panel's
/// buttons run the same ids.
public enum UpdateCommands {
    @MainActor
    public static func all(_ updates: UpdateController) -> [Command] {
        [
            Command(id: "app.check-for-updates", title: T("Check for Updates…", "Procurar atualizações…"),
                    keywords: ["update", "upgrade", "version", "atualizar", "versão", "nova"], category: .app,
                    action: .run { [weak updates] in updates?.showAndCheck() },
                    unavailableReason: { [weak updates] in updates?.unavailableReason }),
            Command(id: "app.install-update", title: T("Install Update and Reopen", "Instalar atualização e reabrir"),
                    keywords: ["update", "upgrade", "atualizar", "instalar"], category: .app,
                    action: .run { [weak updates] in updates?.install() },
                    unavailableReason: { [weak updates] in
                        guard let updates else { return nil }
                        if let reason = updates.unavailableReason { return reason }
                        switch updates.state {
                        case .available, .installed: return nil
                        case .downloading: return T("Already downloading", "Já está baixando")
                        default: return T("No update found", "Nenhuma atualização encontrada")
                        }
                    }),
            Command(id: "app.skip-update", title: T("Don't Remind Me About This Update", "Não lembrar desta atualização"),
                    keywords: ["update", "skip", "ignore", "atualizar", "pular", "ignorar"], category: .app,
                    action: .run { [weak updates] in updates?.skip() },
                    unavailableReason: { [weak updates] in
                        guard let updates, case .available = updates.state else {
                            return T("No update waiting", "Nenhuma atualização esperando")
                        }
                        return nil
                    }),
        ]
    }
}
