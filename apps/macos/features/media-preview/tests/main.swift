import AppKit
import Checks
@testable import Explorer
@testable import MediaPreview

// Tests of the media-preview feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
    ("⌘+scroll zooms around the pointer; dragging moves the image with the hand", {
        expect(ImageScrollView.zoomFactor(deltaY: 10, precise: true) == 1.1)
        expect(ImageScrollView.zoomFactor(deltaY: -10, precise: true) == 0.9)
        expect(ImageScrollView.zoomFactor(deltaY: 500, precise: true) == 2, "a fling zooms at most 2× a step")
        expect(abs(ImageScrollView.zoomFactor(deltaY: 1, precise: false) - 1.1) < 0.0001)
        let origin = ImageScrollView.dragOrigin(start: NSPoint(x: 100, y: 100), from: NSPoint(x: 50, y: 50),
                                                to: NSPoint(x: 70, y: 40), magnification: 2)
        expect(origin == NSPoint(x: 90, y: 105), "\(origin)")
    }),
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
