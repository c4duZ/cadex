import AppKit
import Checks
@testable import Explorer
@testable import SourceControl

// Plan 21 phase C: a real conflict resolved in its tab, and a changed image
// in the review and in the diff.

/// A repository in `dir` with git set up and the folder authorized.
@MainActor
func freshRepo(_ name: String) -> String {
    let dir = NSTemporaryDirectory() + "cadex-\(name)-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let real = URL(fileURLWithPath: dir).resolvingSymlinksInPath().path
    for args in [["init", "-q", "-b", "main"], ["config", "user.name", "T"], ["config", "user.email", "t@cadex"]] { git(args, in: real) }
    WorkspaceFolder(arguments: ["Cadex"], cwd: "/").open(real)
    return real
}

func write(_ text: String, _ path: String) {
    FileManager.default.createFile(atPath: path, contents: Data(text.utf8))
}

/// A small PNG of one color.
@MainActor
func png(_ color: NSColor, size: Int = 8) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    color.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let conflictChecks: [(name: String, body: Checks.Body)] = [
    ("a real conflict in its tab: one block, theirs kept, refused with a marker, then resolved and staged", {
        let repo = freshRepo("conflict")
        defer { try? FileManager.default.removeItem(atPath: repo) }
        write("top\nmiddle\nend\n", repo + "/c.txt")
        git(["add", "."], in: repo)
        git(["commit", "-qm", "base"], in: repo)
        git(["switch", "-qc", "other"], in: repo)
        write("top\ntheirs\nend\n", repo + "/c.txt")
        git(["commit", "-qam", "theirs"], in: repo)
        git(["switch", "-q", "main"], in: repo)
        write("top\nours\nend\n", repo + "/c.txt")
        git(["commit", "-qam", "ours"], in: repo)
        git(["merge", "-q", "other"], in: repo)
        let doc = ConflictDocument(repo: repo, path: "c.txt")
        let loaded = await eventually { doc.blocksLeft == 1 }
        expect(loaded, doc.text)
        // In a window the result has room (it came up with no height, 2026-11-15).
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = doc.view
        doc.view.layoutSubtreeIfNeeded()
        expect((doc.resultText.enclosingScrollView?.frame.height ?? 0) > 200, "\(doc.resultText.enclosingScrollView?.frame ?? .zero)")
        doc.markResolved()
        expect(gitOutput(["diff", "--name-only", "--diff-filter=U"], in: repo).contains("c.txt"), "a marker left: still in conflict")
        doc.accept(.theirs)
        expect(doc.text == "top\ntheirs\nend\n" && doc.blocksLeft == 0, doc.text)
        doc.markResolved()
        let staged = await eventually { gitOutput(["diff", "--name-only", "--diff-filter=U"], in: repo).isEmpty }
        expect(staged, gitOutput(["status", "--short"], in: repo))
        expect((try? String(contentsOfFile: repo + "/c.txt", encoding: .utf8)) == "top\ntheirs\nend\n")
    }),
    ("a changed image: both versions in the review and in the panel's diff, and the modes cycle", {
        let repo = freshRepo("image")
        defer { try? FileManager.default.removeItem(atPath: repo) }
        FileManager.default.createFile(atPath: repo + "/logo.png", contents: png(.red))
        git(["add", "."], in: repo)
        git(["commit", "-qm", "red"], in: repo)
        FileManager.default.createFile(atPath: repo + "/logo.png", contents: png(.blue, size: 16))
        let review = ReviewDocument(request: .init(repo: repo, base: "HEAD"))
        let shown = await eventually { review.hasImages }
        expect(shown, "\(review.text.layout.rows)")
        expect(review.files.first?.beforeData != nil && review.files.first?.afterData != nil)
        let images = review.text.subviews.compactMap { $0 as? ImageDiffView }
        expect(images.count == 1 && images.first?.isEmpty == false, "\(images.count)")
        review.cycleImageMode()
        expect(images.first?.mode == .slide)
        let diff = DiffDocument(request: .init(repo: repo, path: "logo.png", orig: "", staged: false))
        let drawn = await eventually { diff.showsImage }
        expect(drawn, "the panel's diff shows the image")
        diff.cycleImageMode()
        expect(diff.imageMode == .slide && diff.imageView?.mode == .slide)
        // Above 20 MB: no image, the sizes.
        var big = review.files[0]
        big.afterData = Data(count: ImageDiffView.maxBytes + 1)
        expect(!big.showsImage)
        let layout = ReviewLayout(files: [big], options: .init()) { _ in "sizes" }
        expect(layout.rows == [.header(file: 0), .note(file: 0, text: "sizes")])
        let text = ImageDiffView.describe("After", png(.blue, size: 16), NSImage(data: png(.blue, size: 16)))
        expect(text.hasPrefix("After: 16×16"), text)
    }),
]
