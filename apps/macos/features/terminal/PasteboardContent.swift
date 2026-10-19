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

/// Pasted images become PNG files the shell can point to, kept in
/// <temporary directory>/cadex-paste/ and removed after a week so they do
/// not pile up (docs/plans/1-terminal.md).
enum PastedImageStore {
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("cadex-paste", isDirectory: true)
    }

    static func save(_ png: Data, in directory: URL = directory, now: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        // The suffix keeps two pastes in the same second apart.
        let name = "paste-\(formatter.string(from: now))-\(UUID().uuidString.prefix(4)).png"
        let url = directory.appendingPathComponent(name)
        try png.write(to: url)
        return url
    }

    /// Deletes images older than maxAge. Errors are ignored: a file that
    /// stays is harmless, and this runs while the app opens.
    static func removeOld(in directory: URL = directory, now: Date = Date()) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.pathExtension == "png" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) > maxAge {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
