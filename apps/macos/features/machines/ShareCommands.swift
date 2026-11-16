import AppKit
import CommandPalette
import Icons
import Strings

/// What the app gives the sharing commands: the focused preview's local
/// port, the confirmation for the internet, and how to show the address.
public struct ShareActions {
    public var focusedLocalPort: @MainActor () -> Int?
    public var confirmPublic: @MainActor (Int, @escaping @MainActor () -> Void) -> Void
    public var shared: @MainActor (String) -> Void
    public var failed: @MainActor (String) -> Void

    public init(focusedLocalPort: @escaping @MainActor () -> Int?, confirmPublic: @escaping @MainActor (Int, @escaping @MainActor () -> Void) -> Void,
                shared: @escaping @MainActor (String) -> Void, failed: @escaping @MainActor (String) -> Void) {
        self.focusedLocalPort = focusedLocalPort
        self.confirmPublic = confirmPublic
        self.shared = shared
        self.failed = failed
    }
}

/// machines.share-port, machines.stop-sharing and machines.share-public
/// (ADR 0005; docs/spec/machines.md): only by command, through the owner's
/// `tailscale` CLI, undoing only Cadex's own.
@MainActor
public enum ShareCommands {
    public static func all(palette: CommandPaletteController, actions: ShareActions) -> [Command] {
        let controller = MachinesController.shared
        let noServer: @MainActor () -> String? = {
            guard controller.isEnabled, controller.daemon.cli() != nil else { return T("Tailscale is not running", "O Tailscale não está rodando") }
            return actions.focusedLocalPort() == nil ? T("Open a local server in a preview tab first", "Abra antes um servidor local numa aba de preview") : nil
        }
        return [
            Command(id: "machines.share-port", title: T("Share This Preview on Your Tailnet", "Compartilhar este preview na sua tailnet"),
                    keywords: ["tailscale", "serve", "share", "phone", "compartilhar", "celular", "tailnet"], category: .view,
                    action: .run { if let port = actions.focusedLocalPort() { share(port, isPublic: false, actions) } },
                    unavailableReason: noServer),
            Command(id: "machines.share-public", title: T("Share This Preview on the Internet…", "Compartilhar este preview na internet…"),
                    keywords: ["tailscale", "funnel", "public", "internet", "público"], category: .view,
                    action: .run {
                        guard let port = actions.focusedLocalPort() else { return }
                        actions.confirmPublic(port) { share(port, isPublic: true, actions) }
                    },
                    unavailableReason: {
                        if let reason = noServer() { return reason }
                        return controller.status?.funnelAllowed == true ? nil : T("Your tailnet does not let this Mac use Funnel", "Sua tailnet não deixa este Mac usar o Funnel")
                    }),
            Command(id: "machines.stop-sharing", title: T("Stop Sharing a Preview…", "Parar de compartilhar um preview…"),
                    keywords: ["tailscale", "serve", "funnel", "stop", "parar", "compartilhar"], category: .view,
                    action: .run { palette.open(ShareSource(actions: actions)) },
                    unavailableReason: { TailnetShares.shared.all.isEmpty ? T("Cadex shares nothing now", "O Cadex não compartilha nada agora") : nil }),
        ]
    }

    static func share(_ port: Int, isPublic: Bool, _ actions: ShareActions) {
        Task {
            switch await MachinesController.shared.share(localPort: port, isPublic: isPublic) {
            case .success(let url): actions.shared(url)
            case .failure(.message(let message)): actions.failed(message)
            }
        }
    }
}

/// ⌘K's list of what Cadex shares; choosing one turns it off.
@MainActor
final class ShareSource: PaletteSource {
    private let actions: ShareActions
    init(actions: ShareActions) { self.actions = actions }

    var placeholder: String { T("Stop sharing", "Parar de compartilhar") }
    var emptyText: String { T("Cadex shares nothing now", "O Cadex não compartilha nada agora") }
    var icon: Icon { .globe }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        let name = MachinesController.shared.status?.machines.first(where: \.isSelf)?.dnsName ?? "this Mac"
        show(TailnetShares.shared.all.map { share in
            PaletteItem(id: "\(share.httpsPort)", title: "localhost:\(share.localPort)",
                        detail: (share.isPublic ? T("internet · ", "internet · ") : "") + TailscaleServe.url(dnsName: name, httpsPort: share.httpsPort), icon: .globe)
        }, nil)
    }

    func choose(_ item: PaletteItem) {
        guard let share = TailnetShares.shared.all.first(where: { "\($0.httpsPort)" == item.id }) else { return }
        Task {
            if let error = await MachinesController.shared.stopSharing(share) { actions.failed(error) }
        }
    }

    func stop() {}
}
