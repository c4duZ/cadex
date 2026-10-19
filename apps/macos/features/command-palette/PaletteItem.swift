import AppKit
import Icons

/// One row of the palette, whatever lists it (commands, files, text).
public struct PaletteItem: Equatable {
    public let id: String
    public let title: String
    /// Ranges of the title to draw in bold: the letters the search matched.
    public let bold: [Range<String.Index>]
    /// On the right, in grey: a file's folder, "path:line".
    public let detail: String?
    /// A command's shortcut ("⇧⌘D"), drawn as keys on the right.
    public let shortcut: String?
    /// Why it cannot run now; the row is greyed out.
    public let unavailableReason: String?
    /// The rows of one section go under a title; nil, no title.
    public var section: String?
    /// A Phosphor glyph on the left, tinted like the text.
    public let icon: Icon?
    /// A picture on the left instead (a file type's Material icon).
    public let image: NSImage?

    public init(id: String, title: String, bold: [Range<String.Index>] = [], detail: String? = nil,
                shortcut: String? = nil, unavailableReason: String? = nil, section: String? = nil,
                icon: Icon? = nil, image: NSImage? = nil) {
        self.id = id
        self.title = title
        self.bold = bold
        self.detail = detail
        self.shortcut = shortcut
        self.unavailableReason = unavailableReason
        self.section = section
        self.icon = icon
        self.image = image
    }

    public static func == (a: PaletteItem, b: PaletteItem) -> Bool {
        a.id == b.id && a.title == b.title && a.bold == b.bold && a.detail == b.detail && a.shortcut == b.shortcut
            && a.unavailableReason == b.unavailableReason && a.section == b.section && a.icon == b.icon
    }

    /// The characters at the matched UTF-8 offsets, as ranges of `text`:
    /// what the core's fuzzy ranking returns, made drawable.
    public static func boldRanges(in text: String, byteOffsets: [Int]) -> [Range<String.Index>] {
        let utf8 = text.utf8
        return byteOffsets.compactMap { offset in
            guard offset < utf8.count else { return nil }
            let start = utf8.index(utf8.startIndex, offsetBy: offset)
            guard let char = String.Index(start, within: text) else { return nil }
            return char..<text.index(after: char)
        }
    }
}

/// A key the list answers to, shown in the palette's footer: "⌥↩ ao lado".
public struct PaletteHint: Equatable, Sendable {
    public let keys: String
    public let label: String

    public init(_ keys: String, _ label: String) {
        self.keys = keys
        self.label = label
    }
}

/// How the row was chosen: Return alone, or with ⌥ or ⌘ (docs/spec/command-palette.md).
public enum PaletteChoice: Sendable {
    case primary, option, command
}
