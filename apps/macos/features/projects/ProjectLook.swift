import AppKit

/// How a project shows itself (plan 36 phase B; docs/adr/0038-rail-and-side-column.md): the name
/// the owner gave (not the folder's), its color, and a picture or an emoji in place of the letter.
public struct ProjectLook: Equatable, Sendable {
    public var name: String
    /// A work color's name ("blue"); nil: none.
    public var color: String?
    /// The picture's file name in `ProjectsController.imagesFolder`.
    public var image: String?
    public var emoji: String?

    public init(name: String, color: String? = nil, image: String? = nil, emoji: String? = nil) {
        self.name = name
        self.color = color
        self.image = image
        self.emoji = emoji
    }
}

extension ProjectsController {
    /// The pictures' folder: project-images next to the projects file (the owner's Application
    /// Support/Cadex, or a test instance's own folder). A copy, so a picture moved or deleted at
    /// its origin stays.
    public var imagesFolder: URL {
        (fileURL ?? ProjectsFile.defaultURL).deletingLastPathComponent().appendingPathComponent("project-images")
    }

    /// The file of a picture's name; nil without one or when it is gone.
    public func imageURL(_ name: String?) -> URL? {
        guard let name, !name.isEmpty else { return nil }
        let url = imagesFolder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func look(of folder: String) -> ProjectLook? {
        projects.first { $0.folder == folder }.map { ProjectLook(name: $0.name, color: $0.color, image: $0.image, emoji: $0.emoji) }
    }

    /// The project of `folder` takes the look; an empty name goes back to the folder's, and a
    /// picture replaced leaves the folder.
    public func setLook(_ look: ProjectLook, for folder: String) {
        guard let project = projects.first(where: { $0.folder == folder }) else { return }
        let trimmed = look.name.trimmingCharacters(in: .whitespaces)
        project.name = trimmed.isEmpty ? Self.name(of: folder) : trimmed
        project.color = look.color
        if let old = project.image, old != look.image, let url = imageURL(old) { try? FileManager.default.removeItem(at: url) }
        project.image = look.image
        let emoji = look.emoji?.trimmingCharacters(in: .whitespaces)
        project.emoji = emoji?.isEmpty == false ? emoji : nil
        onChange?()
        scheduleSave()
    }

    /// The picture at `url` copied into `imagesFolder`, cut square from its middle and made small
    /// (`side` points at 2×), as PNG; its name, or nil when it does not read as an image.
    public func storeImage(from url: URL, side: CGFloat = 64) -> String? {
        guard let image = NSImage(contentsOf: url), let data = Self.squarePNG(image, pixels: Int(side * 2)) else { return nil }
        let name = UUID().uuidString + ".png"
        do {
            try FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
            try data.write(to: imagesFolder.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    /// The middle square of `image`, `pixels` wide, as PNG.
    static func squarePNG(_ image: NSImage, pixels: Int) -> Data? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil), source.width > 0, source.height > 0 else { return nil }
        let side = min(source.width, source.height)
        let crop = CGRect(x: (source.width - side) / 2, y: (source.height - side) / 2, width: side, height: side)
        guard let square = source.cropping(to: crop),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(square, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        guard let out = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
    }
}

/// A project's tile as the pages draw it (the Projects cards, the project page's head): the
/// picture's file, the emoji, the color; the app gathers it from the look.
public struct ProjectPicture: Equatable {
    public var image: String?
    public var emoji: String?
    public var tint: NSColor?

    public init(image: String? = nil, emoji: String? = nil, tint: NSColor? = nil) {
        self.image = image
        self.emoji = emoji
        self.tint = tint
    }
}
