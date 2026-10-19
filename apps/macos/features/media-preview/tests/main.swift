import AppKit
import Checks
@testable import Explorer
@testable import MediaPreview

// Tests of the media-preview feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
    ("the viewer comes from the file type", {
        expect(MediaKind.of(path: "a/icon.png") == .image)
        expect(MediaKind.of(path: "logo.SVG") == .image)
        expect(MediaKind.of(path: "spec.pdf") == .pdf)
        expect(MediaKind.of(path: "demo.mov") == .video)
        expect(MediaKind.of(path: "song.mp3") == .audio)
        expect(MediaKind.of(path: "pacote.zip") == .quickLook)
        expect(MediaKind.of(path: "render.zig") == nil)
        expect(MediaKind.of(path: "README.md") == nil)
        expect(MediaKind.of(path: "data.json") == nil)
        expect(MediaKind.of(path: "Makefile") == nil)
        expect(MediaKind.of(path: "notes.whatever") == nil)
    }),
    ("an image opens with its size; outside the workspace it does not", {
        let dir = NSTemporaryDirectory() + "cadex-media-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let image = NSImage(size: NSSize(width: 40, height: 20), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: URL(fileURLWithPath: dir + "/a.png"))
        let outside = MediaDocument(path: dir + "/a.png", kind: .image)
        expect(outside.image == nil)
        let folder = WorkspaceFolder(arguments: ["Cadex"], cwd: "/")
        folder.open(dir)
        let doc = MediaDocument(path: folder.root + "/a.png", kind: .image)
        expect(doc.image?.hasImage == true)
        try? FileManager.default.removeItem(atPath: dir)
    }),
])
exit(exitCode)
