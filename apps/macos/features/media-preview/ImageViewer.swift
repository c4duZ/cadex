import AppKit

/// An image in a tab (docs/spec/media-preview.md): fitted to the tab when
/// bigger, zoom with ⌘+ ⌘− ⌘0 ⌘1, a soft checkerboard behind transparency,
/// size and dimensions at the bottom. GIFs animate.
@MainActor
final class ImageViewer: NSView {
    private let scroll = NSScrollView()
    private let imageView = NSImageView()
    private let info = NSTextField(labelWithString: "")
    private var fitted = true
    private var pixelSize: NSSize = .zero

    init(path: String) {
        super.init(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.05
        scroll.maxMagnification = 16
        scroll.drawsBackground = true
        scroll.backgroundColor = Self.checkerboard()
        imageView.imageScaling = .scaleNone
        imageView.animates = true
        scroll.documentView = imageView
        info.font = .systemFont(ofSize: 11)
        info.textColor = .secondaryLabelColor
        info.alignment = .center
        for v in [scroll, info] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: info.topAnchor, constant: -4),
            info.leadingAnchor.constraint(equalTo: leadingAnchor),
            info.trailingAnchor.constraint(equalTo: trailingAnchor),
            info.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        load(path)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ImageViewer is created in code") }

    var hasImage: Bool { imageView.image != nil }

    func load(_ path: String) {
        guard let image = NSImage(contentsOfFile: path) else {
            imageView.image = nil
            info.stringValue = "Não é possível mostrar esta imagem"
            return
        }
        // The largest representation's pixels: an @2x PNG shows its real size.
        let rep = image.representations.max { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }
        pixelSize = NSSize(width: rep?.pixelsWide ?? Int(image.size.width), height: rep?.pixelsHigh ?? Int(image.size.height))
        if pixelSize.width <= 0 { pixelSize = image.size }
        image.size = pixelSize
        imageView.image = image
        imageView.frame = NSRect(origin: .zero, size: pixelSize)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        info.stringValue = "\(Int(pixelSize.width)) × \(Int(pixelSize.height)) · " +
            ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        if fitted { fit() }
    }

    override func layout() {
        super.layout()
        if fitted { fit() }
    }

    /// ⌘0: the whole image in the tab (never bigger than its real size).
    func fit() {
        fitted = true
        guard pixelSize.width > 0, scroll.bounds.width > 0 else { return }
        let scale = min(scroll.bounds.width / pixelSize.width, scroll.bounds.height / pixelSize.height, 1)
        scroll.magnification = scale
        centerImage()
    }

    /// ⌘1: real size.
    func actualSize() {
        fitted = false
        scroll.magnification = 1
        centerImage()
    }

    func zoom(by factor: CGFloat) {
        fitted = false
        scroll.magnification *= factor
    }

    private func centerImage() {
        let clip = scroll.contentView
        let visible = clip.bounds.size
        let origin = NSPoint(x: (pixelSize.width - visible.width) / 2, y: (pixelSize.height - visible.height) / 2)
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
    }

    /// A discreet checkerboard, so transparency reads as transparency.
    static func checkerboard() -> NSColor {
        let size: CGFloat = 16
        let tile = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor(white: 0.5, alpha: 0.10).setFill()
            rect.fill()
            NSColor(white: 0.5, alpha: 0.20).setFill()
            NSRect(x: 0, y: 0, width: size / 2, height: size / 2).fill()
            NSRect(x: size / 2, y: size / 2, width: size / 2, height: size / 2).fill()
            return true
        }
        return NSColor(patternImage: tile)
    }
}
