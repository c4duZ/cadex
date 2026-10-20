// Draws each .pdf of a folder as square PNGs of the given sizes, named
// <icon>-<size>.png, into another folder (tools/icons/windows_file_icons.py
// runs it). The Windows app draws the Material file icons as bitmaps: the
// vector path (Direct2D's SVG) has no C interface in the SDK headers the app
// uses (docs/adr/0011-material-file-icons.md).
//
//   swift tools/icons/pdf_to_png.swift <pdf folder> <png folder> 32 64
import AppKit

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let sizes = CommandLine.arguments.dropFirst(3).compactMap { Int($0) }
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let files = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
var written = 0
for pdf in files.sorted(by: { $0.path < $1.path }) where pdf.pathExtension == "pdf" {
    guard let image = NSImage(contentsOf: pdf) else {
        print("não li:", pdf.lastPathComponent)
        continue
    }
    for size in sizes {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { continue }
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { continue }
        let name = pdf.deletingPathExtension().lastPathComponent + "-\(size).png"
        try png.write(to: output.appendingPathComponent(name))
        written += 1
    }
}
print("\(written) PNGs em \(output.path)")
