import AppKit

/// The thumbnail of a pasted image, shown while the pointer is on its
/// "[Image #N]" tag (TerminalPastedImages.swift).
final class PastedImageHover: NSView {
    /// docs/spec/terminal.md: at most 320 × 240 pt.
    static let maxSize = CGSize(width: 320, height: 240)
    private static let inset: CGFloat = 4

    let file: URL

    /// nil when the file is not an image the system reads.
    init?(file: URL) {
        guard let image = NSImage(contentsOf: file), image.size.width > 0, image.size.height > 0 else { return nil }
        self.file = file
        let fit = min(1, Self.maxSize.width / image.size.width, Self.maxSize.height / image.size.height)
        let shown = CGSize(width: (image.size.width * fit).rounded(), height: (image.size.height * fit).rounded())
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: shown.width + Self.inset * 2, height: shown.height + Self.inset * 2)))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        let view = NSImageView(frame: CGRect(x: Self.inset, y: Self.inset, width: shown.width, height: shown.height))
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        view.wantsLayer = true
        view.layer?.cornerRadius = 5
        view.layer?.masksToBounds = true
        addSubview(view)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PastedImageHover is created in code") }

    /// The pointer stays on the tag: clicks pass through to the terminal.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Below the tag, or above it when there is no room; kept inside the
    /// terminal.
    func place(below tag: CGRect, in area: CGRect) {
        let gap: CGFloat = 4
        var origin = CGPoint(x: tag.minX, y: tag.minY - gap - frame.height)
        if origin.y < area.minY { origin.y = tag.maxY + gap }
        origin.x = min(max(origin.x, area.minX + gap), area.maxX - frame.width - gap)
        origin.y = min(max(origin.y, area.minY + gap), area.maxY - frame.height - gap)
        setFrameOrigin(origin)
    }
}
