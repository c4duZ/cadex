import AppKit
import Darwin
import Strings
import UILooks

/// What a preview with no page shows (the owner, 2026-11-18: a blank tab was a gray page with a
/// green dot and "Pick element" lit, saying nothing): what to do, and the local servers that
/// answer now, one click each. The same view says why a page could not load.
@MainActor
final class PreviewStart: NSView {
    typealias B = DesignTokens.Preview
    /// Opens an address in this tab.
    var open: ((String) -> Void)?
    private let heading = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let servers = NSStackView()
    private let note = NSTextField(wrappingLabelWithString: "")
    private var scanning = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        heading.font = UILooks.font(DesignTokens.FontSize.prompt, weight: .semibold)
        heading.textColor = DesignTokens.Color.textPrimary
        for label in [detail, note] {
            label.font = UILooks.font(DesignTokens.FontSize.body)
            label.textColor = DesignTokens.Color.textSecondary
            label.alignment = .center
        }
        servers.spacing = UILooks.pt(B.Bar.gap)
        let stack = NSStackView(views: [heading, detail, servers, note])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = UILooks.pt(B.Bar.padding.left)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PreviewStart is created in code") }

    /// A blank tab: what to type, and the servers found.
    func showBlank() {
        show(T("Open a page", "Abrir uma página"), T("Type an address above, or open a server running on this Mac.",
                                                      "Digite um endereço acima, ou abra um servidor rodando neste Mac."))
    }

    /// A page that did not load: the address and the system's reason, and the servers found.
    func showFailure(_ address: String, _ reason: String) {
        show(T("Nothing at \(Self.short(address))", "Nada em \(Self.short(address))"), reason)
    }

    private func show(_ title: String, _ text: String) {
        heading.stringValue = title
        detail.stringValue = text
        isHidden = false
        scan()
    }

    /// Asks the usual ports again, off the main thread; the buttons come when it answers.
    func scan() {
        guard !scanning else { return }
        scanning = true
        note.stringValue = T("Looking for local servers…", "Procurando servidores locais…")
        servers.isHidden = true
        Task { [weak self] in
            let ports = await LocalServers.listening()
            self?.showServers(ports)
        }
    }

    private func showServers(_ ports: [Int]) {
        scanning = false
        servers.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for port in ports {
            let address = "localhost:\(port)"
            servers.addArrangedSubview(DesignButton.make(address, .secondary) { [weak self] in self?.open?(address) })
        }
        servers.isHidden = ports.isEmpty
        note.stringValue = ports.isEmpty
            ? T("No local server answers on the usual ports. Start one in a terminal (npm run dev) and reload.",
                "Nenhum servidor local responde nas portas de sempre. Rode um num terminal (npm run dev) e recarregue.")
            : T("Servers answering on this Mac", "Servidores respondendo neste Mac")
    }

    static func short(_ address: String) -> String {
        address.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

/// The local dev servers: which of the usual ports accept a connection on 127.0.0.1. 5000 and
/// 7000 are left out: macOS's AirPlay Receiver listens there.
enum LocalServers {
    static let ports = [3000, 3001, 3002, 4000, 4200, 4321, 5173, 5174, 8000, 8080, 8081, 8888, 9000]

    static func listening(_ ports: [Int] = ports) async -> [Int] {
        await withTaskGroup(of: Int?.self) { group in
            for port in ports { group.addTask { isOpen(port) ? port : nil } }
            var open: [Int] = []
            for await port in group { if let port { open.append(port) } }
            return open.sorted()
        }
    }

    /// A non-blocking connect that waits at most 100 ms: a closed port refuses at once.
    nonisolated static func isOpen(_ port: Int, timeoutMs: Int32 = 100) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let started = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if started == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var poller = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&poller, 1, timeoutMs) == 1 else { return false }
        var failure: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &failure, &length)
        return failure == 0
    }
}
