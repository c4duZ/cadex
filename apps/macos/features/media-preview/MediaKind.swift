import Foundation
import UniformTypeIdentifiers

/// Which viewer a file opens in (docs/spec/media-preview.md), by its type
/// as the system knows it from the extension. Text and unknown types are
/// the editor's: it reads the bytes and says when they are binary.
public enum MediaKind: Equatable, Sendable {
    case image
    case video
    case audio
    case pdf
    /// Not text and none of the above: Quick Look shows what it can.
    case quickLook

    /// Nil when the file belongs in the editor.
    public static func of(path: String) -> MediaKind? {
        let ext = (path as NSString).pathExtension.lowercased()
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return nil }
        // SVG is text the editor reads too, but people open it to see it.
        if type.conforms(to: .svg) || type.conforms(to: .image) { return .image }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .script)
            || type.conforms(to: .json) || type.conforms(to: .xml) || type.conforms(to: .propertyList) { return nil }
        // Types the system made up for an extension it does not know
        // (dyn.*) are not "not text": let the editor look at the bytes.
        if type.isDynamic { return nil }
        return .quickLook
    }
}
