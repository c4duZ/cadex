import AppKit
import UILooks
import AVKit
import CCadex
import Quartz
import Tabs
import Strings

/// An image, a video, an audio file, a PDF or anything Quick Look shows,
/// in a tab (docs/spec/media-preview.md). The file is read by the system's
/// frameworks after the core says it is inside the workspace.
@MainActor
public final class MediaDocument: TabDocument {
    public let path: String
    public let kind: MediaKind
    public let view = NSView()
    public var onChange: (() -> Void)?
    /// "Abrir no app padrão" when the system cannot show the file.
    public var openExternally: ((String) -> Void)?
    private(set) var image: ImageViewer?
    private(set) var pdf: PDFViewer?
    private var player: AVPlayerView?
    private var quickLook: QLPreviewView?
    private var buttonAction: ButtonAction?

    public init(path: String, kind: MediaKind) {
        self.path = path
        self.kind = kind
        guard cadex_workspace_is_authorized(path) else {
            show(message: T("The file is outside the open folder", "O arquivo está fora da pasta aberta"))
            return
        }
        switch kind {
        case .image: showImage()
        case .pdf: showPDF()
        case .video, .audio: showPlayer()
        case .quickLook: showQuickLook()
        }
    }

    public var title: String { (path as NSString).lastPathComponent }
    public var identity: String { path }
    public var hasUnsavedChanges: Bool { false }

    public func focus() {
        let target: NSView? = pdf?.pdfView ?? player ?? quickLook ?? image
        view.window?.makeFirstResponder(target)
    }

    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) {
        close()
    }

    public func close() {
        player?.player?.pause()
        player?.player = nil
        quickLook?.close()
    }

    /// The file changed on disk: show it again.
    public func diskMayHaveChanged() {
        image?.load(path)
        pdf?.load(path)
        if quickLook != nil { quickLook?.refreshPreviewItem() }
    }

    // MARK: Zoom (images and PDFs)

    public func zoomIn() { image?.zoom(by: 1.25) ?? pdf?.pdfView.zoomIn(nil) }
    public func zoomOut() { image?.zoom(by: 0.8) ?? pdf?.pdfView.zoomOut(nil) }
    public func zoomToFit() {
        image?.fit()
        pdf?.pdfView.autoScales = true
    }
    public func actualSize() {
        image?.actualSize()
        pdf?.pdfView.scaleFactor = 1
    }

    // MARK: Views

    private func showImage() {
        let viewer = ImageViewer(path: path)
        guard viewer.hasImage else { return show(message: T("Can't show this image", "Não é possível mostrar esta imagem")) }
        image = viewer
        fill(viewer)
    }

    private func showPDF() {
        let viewer = PDFViewer(path: path)
        guard viewer.hasDocument else { return show(message: T("Can't open this PDF", "Não é possível abrir este PDF")) }
        pdf = viewer
        fill(viewer)
    }

    /// Video and audio with the system's controls; nothing plays until the
    /// user presses play.
    private func showPlayer() {
        let playerView = AVPlayerView()
        let item = AVPlayerItem(url: URL(fileURLWithPath: path))
        playerView.player = AVPlayer(playerItem: item)
        playerView.controlsStyle = .floating
        playerView.showsFullScreenToggleButton = kind == .video
        player = playerView
        fill(playerView)
        Task { @MainActor [weak self] in
            // A file the system cannot decode: say so instead of a black view.
            guard let playable = try? await item.asset.load(.isPlayable), playable else {
                self?.show(message: T("Can't play this file", "Não é possível tocar este arquivo"))
                return
            }
        }
    }

    private func showQuickLook() {
        guard let preview = QLPreviewView(frame: .zero, style: .normal) else { return show(message: T("Can't show this file", "Não é possível mostrar este arquivo")) }
        preview.previewItem = URL(fileURLWithPath: path) as NSURL
        preview.shouldCloseWithWindow = false
        quickLook = preview
        fill(preview)
    }

    private func show(message: String) {
        let label = NSTextField(labelWithString: message)
        label.font = UILooks.font(14)
        label.textColor = .secondaryLabelColor
        let action = ButtonAction { [weak self] in
            guard let self else { return }
            self.openExternally?(self.path)
        }
        buttonAction = action
        let button = NSButton(title: T("Open in Default App", "Abrir no app padrão"), target: action, action: #selector(ButtonAction.run))
        let stack = NSStackView(views: [label, button])
        stack.orientation = .vertical
        stack.spacing = 12
        let container = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        fill(container)
    }

    private func fill(_ content: NSView) {
        view.subviews.forEach { $0.removeFromSuperview() }
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

/// A closure as a button's target (the document is not an NSObject).
private final class ButtonAction: NSObject {
    let body: () -> Void
    init(_ body: @escaping () -> Void) { self.body = body }
    @objc func run() { body() }
}
