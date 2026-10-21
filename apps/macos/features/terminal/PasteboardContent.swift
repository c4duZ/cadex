import AppKit

/// What ⌘V pastes, picked from the clipboard in the order of
/// docs/spec/terminal.md: files first, then an image, then text.
enum PasteContent: Equatable {
    case files([URL])
    /// The image as PNG, ready to be saved to a file.
    case image(Data)
    case text(String)

    /// nil when there is nothing to paste: ⌘V then sends nothing.
    static func read(from pasteboard: NSPasteboard) -> PasteContent? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
            return .files(urls)
        }
        // A browser copies an image together with text (its address or alt
        // text); the spec says the image wins.
        if let png = pngImage(from: pasteboard) {
            return .image(png)
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return .text(text)
        }
        return nil
    }

    private static func pngImage(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        // Screenshots and most apps put TIFF on the clipboard.
        guard let tiff = pasteboard.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

