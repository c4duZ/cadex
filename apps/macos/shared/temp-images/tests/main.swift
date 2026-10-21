import AppKit
import Checks
import TempImages

// Tests of the temporary images. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
    ("images are saved as PNG and removed after a week", {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cadex-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TempImageStore(directory: dir, prefix: "paste")
        let old = try store.save(Data([0x89, 0x50]))
        let recent = try store.save(Data([0x89, 0x50]))
        let eightDaysAgo = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: eightDaysAgo], ofItemAtPath: old.path)
        expect(old != recent && old.pathExtension == "png" && old.lastPathComponent.hasPrefix("paste-"))

        store.removeOld()
        expect(!FileManager.default.fileExists(atPath: old.path), "old image stayed")
        expect(FileManager.default.fileExists(atPath: recent.path), "recent image removed")
    }),
    ("each store has its own folder in the temporary directory", {
        let picks = TempImageStore(folder: "cadex-pick", prefix: "pick")
        expect(picks.directory.lastPathComponent == "cadex-pick")
        expect(picks.directory.deletingLastPathComponent().standardizedFileURL == FileManager.default.temporaryDirectory.standardizedFileURL)
    }),
    ("a large image is scaled to 1568 pixels on its longest side; a small one stays", {
        func png(_ width: Int, _ height: Int) -> Data {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0)!
            return rep.representation(using: .png, properties: [:])!
        }
        let big = TempImageStore.fitted(png(2940, 1912))
        let rep = NSBitmapImageRep(data: big)
        expect(rep?.pixelsWide == 1568 && rep?.pixelsHigh == 1020, "\(rep?.pixelsWide ?? 0)×\(rep?.pixelsHigh ?? 0)")
        let small = png(800, 600)
        expect(TempImageStore.fitted(small) == small)
        expect(TempImageStore.fitted(Data([1, 2, 3])) == Data([1, 2, 3]), "not an image: as it came")
    }),
])
exit(exitCode)
