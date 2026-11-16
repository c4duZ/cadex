import AppKit
import Icons
import Strings

/// A small button in the bottom-right corner of the terminal: the offer to
/// open a local server in the preview (docs/spec/preview.md), for a few
/// seconds after the address shows up, and "Restart" when an agent quit
/// (docs/spec/agents.md, Hibernação), until it is used or you type.
final class TerminalOffer: NSView {
    private let button: NSButton
    private var hideTimer: Timer?
    private let act: () -> Void
    /// The agent's "Restart", which typing takes away.
    var isRestart = false

    init(title: String, icon: Icon, act: @escaping () -> Void) {
        self.act = act
        button = NSButton(title: title, target: nil, action: nil)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        button.isBordered = false
        button.image = icon.image(size: 13)
        button.imagePosition = .imageLeading
        button.contentTintColor = .controlAccentColor
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.target = self
        button.action = #selector(pressed)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            button.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TerminalOffer is created in code") }

    @objc private func pressed() {
        removeFromSuperview()
        act()
    }

    /// Goes away by itself after a while.
    func hide(after seconds: TimeInterval) {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeFromSuperview() }
        }
    }
}

extension TerminalView {
    /// Shows the offer for `url` (replacing an older one).
    /// Whether a host that is not this Mac's is a machine the owner has
    /// (plan 23: the core also reports `http://ubuntu-dev:3000`, which may be
    /// a tailnet machine or anything else). The app answers, maybe after
    /// reading the tailnet once; none set, only local addresses are offered.
    public static var isOwnHost: (@MainActor (String, @escaping @MainActor (Bool) -> Void) -> Void)?

    static func isLocal(_ host: String) -> Bool {
        ["localhost", "127.0.0.1", "[::1]"].contains(host)
    }

    static func host(of url: String) -> String {
        let rest = url.replacingOccurrences(of: "http://", with: "")
        if rest.hasPrefix("[") { return String(rest.prefix { $0 != "]" }) + "]" }
        return String(rest.prefix { $0 != ":" && $0 != "/" })
    }

    func offerPreview(_ url: String) {
        let host = Self.host(of: url)
        guard !Self.isLocal(host) else { return showPreviewOffer(url) }
        Self.isOwnHost?(host) { [weak self] own in if own { self?.showPreviewOffer(url) } }
    }

    private func showPreviewOffer(_ url: String) {
        guard let onOpenPreview else { return }
        let shown = url.replacingOccurrences(of: "http://", with: "")
        let offer = place(TerminalOffer(title: T("Open in preview  \(shown)", "Abrir no preview  \(shown)"), icon: .globe) { onOpenPreview(url) })
        offer.hide(after: 10)
    }

    /// "Restart" for an agent that quit (not hibernated): it runs the
    /// app's agents.restart through `onRestartAgent`. Stays until used,
    /// until you type, or until another program runs. False hides it.
    public func offerRestart(_ shown: Bool, agent: String = "Claude") {
        guard shown, let onRestartAgent else {
            if previewOffer?.isRestart == true { previewOffer?.removeFromSuperview() }
            return
        }
        let offer = place(TerminalOffer(title: T("Restart \(agent)", "Reiniciar o \(agent)"), icon: .arrowClockwise) { onRestartAgent() })
        offer.isRestart = true
    }

    private func place(_ offer: TerminalOffer) -> TerminalOffer {
        previewOffer?.removeFromSuperview()
        offer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(offer)
        NSLayoutConstraint.activate([
            offer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            offer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
        previewOffer = offer
        return offer
    }
}
