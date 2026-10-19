// Turns each .svg of a folder into a vector .pdf of the same name and
// removes the .svg (tools/icons/build_file_icons.py runs it). The app runs
// from macOS 13, whose NSImage does not read SVG; PDF it reads everywhere
// (docs/adr/0011-material-file-icons.md). Uses this Mac's AppKit to read the
// SVG, so no converter has to be installed.
//
//   swift tools/icons/svg_to_pdf.swift <folder>
import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
var converted = 0
for svg in files where svg.pathExtension == "svg" {
    guard let image = NSImage(contentsOf: svg) else {
        print("não li:", svg.lastPathComponent)
        continue
    }
    var box = CGRect(origin: .zero, size: image.size)
    let pdf = svg.deletingPathExtension().appendingPathExtension("pdf")
    guard let context = CGContext(pdf as CFURL, mediaBox: &box, nil) else { continue }
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    image.draw(in: box)
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    try FileManager.default.removeItem(at: svg)
    converted += 1
}
print("\(converted) PDFs")
