import AppKit
import Icons

/// The offer to open a local server in the preview (docs/spec/preview.md):
/// a small button in the bottom-right corner of the terminal, for a few
/// seconds after the address shows up in the output.
final class TerminalPreviewOffer: NSView {
    private let button: NSButton
    private var hideTimer: Timer?
    let url: String
    private let open: (String) -> Void

    init(url: String, open: @escaping (String) -> Void) {
        self.url = url
        self.open = open
        let shown = url.replacingOccurrences(of: "http://", with: "")
        button = NSButton(title: "Abrir no preview  \(shown)", target: nil, action: nil)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        button.isBordered = false
        button.image = Icon.globe.image(size: 13)
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
    required init?(coder: NSCoder) { fatalError("TerminalPreviewOffer is created in code") }

    @objc private func pressed() {
        open(url)
        removeFromSuperview()
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
    func offerPreview(_ url: String) {
        guard let onOpenPreview else { return }
        previewOffer?.removeFromSuperview()
        let offer = TerminalPreviewOffer(url: url) { onOpenPreview($0) }
        offer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(offer)
        NSLayoutConstraint.activate([
            offer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            offer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
        offer.hide(after: 10)
        previewOffer = offer
    }
}
