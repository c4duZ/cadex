import AppKit
import Strings
import UILooks

/// How the two versions of an image show (git.review-image-mode cycles).
public enum ImageDiffMode: Int, CaseIterable, Sendable {
    case sideBySide, slide, overlay

    var next: ImageDiffMode { ImageDiffMode(rawValue: (rawValue + 1) % 3) ?? .sideBySide }
    var title: String {
        switch self {
        case .sideBySide: T("Side by side", "Lado a lado")
        case .slide: T("Slide", "Deslizar")
        case .overlay: T("Overlay", "Sobrepor")
        }
    }
}

/// A changed image, before and after (docs/spec/source-control.md, Imagem):
/// side by side, a bar that slides between them, or one over the other with
/// a slider for the opacity; the sizes and dimensions of both below. Read by
/// ImageIO through NSImage (png, jpg, gif, webp, heic, a pdf's first page).
@MainActor
final class ImageDiffView: NSView {
    nonisolated static let maxBytes = 20 * 1024 * 1024
    var mode: ImageDiffMode = .sideBySide { didSet { applyMode() } }
    private let before: NSImage?
    private let after: NSImage?
    private let canvas = ImageCanvas()
    private let info = NSTextField(labelWithString: "")
    private let opacity = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)

    /// `nil` data: that side does not exist (a new or deleted image).
    init(before: Data?, after: Data?) {
        self.before = before.flatMap { $0.isEmpty ? nil : NSImage(data: $0) }
        self.after = after.flatMap { $0.isEmpty ? nil : NSImage(data: $0) }
        super.init(frame: .zero)
        canvas.before = self.before
        canvas.after = self.after
        info.font = UILooks.font(11)
        info.textColor = .secondaryLabelColor
        info.stringValue = [Self.describe(T("Before", "Antes"), before, self.before), Self.describe(T("After", "Depois"), after, self.after)].joined(separator: "   ·   ")
        opacity.target = self
        opacity.action = #selector(opacityChanged)
        opacity.controlSize = .small
        let bottom = NSStackView(views: [info, NSView(), opacity])
        bottom.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        for view in [canvas, bottom] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: topAnchor), canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: trailingAnchor), canvas.bottomAnchor.constraint(equalTo: bottom.topAnchor),
            bottom.leadingAnchor.constraint(equalTo: leadingAnchor), bottom.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: bottomAnchor), opacity.widthAnchor.constraint(equalToConstant: 140),
        ])
        applyMode()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ImageDiffView is created in code") }

    var isEmpty: Bool { before == nil && after == nil }

    private func applyMode() {
        canvas.mode = mode
        opacity.isHidden = mode != .overlay
    }

    @objc private func opacityChanged() {
        canvas.opacity = opacity.doubleValue
    }

    static func describe(_ side: String, _ data: Data?, _ image: NSImage?) -> String {
        guard let data, !data.isEmpty else { return "\(side): —" }
        let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        guard let image, let rep = image.representations.first else { return "\(side): \(size)" }
        let width = rep.pixelsWide > 0 ? rep.pixelsWide : Int(image.size.width)
        let height = rep.pixelsHigh > 0 ? rep.pixelsHigh : Int(image.size.height)
        return "\(side): \(width)×\(height), \(size)"
    }

    nonisolated static func isImage(_ path: String) -> Bool {
        ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "pdf", "tiff", "tif", "bmp"].contains((path as NSString).pathExtension.lowercased())
    }
}

/// Where the two versions are drawn; dragging moves the slide's bar.
@MainActor
final class ImageCanvas: NSView {
    var before: NSImage?
    var after: NSImage?
    var mode: ImageDiffMode = .sideBySide { didSet { needsDisplay = true } }
    var opacity = 0.5 { didSet { needsDisplay = true } }
    private var split: CGFloat = 0.5

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.withAlphaComponent(0.4).setFill()
        bounds.fill()
        let area = bounds.insetBy(dx: 12, dy: 12)
        switch mode {
        case .sideBySide:
            let half = (area.width - 12) / 2
            draw(before, in: NSRect(x: area.minX, y: area.minY, width: half, height: area.height))
            draw(after, in: NSRect(x: area.minX + half + 12, y: area.minY, width: half, height: area.height))
        case .slide:
            let box = fit(after ?? before, in: area)
            draw(after, in: box, exact: true)
            let cut = box.minX + box.width * split
            NSGraphicsContext.saveGraphicsState()
            NSRect(x: box.minX, y: box.minY, width: cut - box.minX, height: box.height).clip()
            draw(before, in: box, exact: true)
            NSGraphicsContext.restoreGraphicsState()
            NSColor.controlAccentColor.setFill()
            NSRect(x: cut - 1, y: box.minY, width: 2, height: box.height).fill()
            NSBezierPath(ovalIn: NSRect(x: cut - 7, y: box.midY - 7, width: 14, height: 14)).fill()
        case .overlay:
            let box = fit(after ?? before, in: area)
            draw(before, in: box, exact: true)
            after?.draw(in: box, from: .zero, operation: .sourceOver, fraction: opacity)
        }
    }

    private func fit(_ image: NSImage?, in area: NSRect) -> NSRect {
        guard let image, image.size.width > 0, image.size.height > 0 else { return area }
        let scale = min(area.width / image.size.width, area.height / image.size.height, 1)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func draw(_ image: NSImage?, in area: NSRect, exact: Bool = false) {
        guard let image else {
            let text = T("(none)", "(nenhuma)") as NSString
            text.draw(at: NSPoint(x: area.midX - 20, y: area.midY), withAttributes: [.foregroundColor: NSColor.tertiaryLabelColor])
            return
        }
        image.draw(in: exact ? area : fit(image, in: area), from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func mouseDown(with event: NSEvent) { slide(event) }
    override func mouseDragged(with event: NSEvent) { slide(event) }

    private func slide(_ event: NSEvent) {
        guard mode == .slide else { return }
        let box = fit(after ?? before, in: bounds.insetBy(dx: 12, dy: 12))
        let x = convert(event.locationInWindow, from: nil).x
        split = min(max((x - box.minX) / max(box.width, 1), 0), 1)
        needsDisplay = true
    }
}
