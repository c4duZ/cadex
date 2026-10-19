// Draws dmg-background.tiff (660×400 plus @2x) next to this script, in the
// app's dark chrome with the default theme's orange. Run by hand when the
// copy or layout changes:
//   swift apps/macos/packaging/dmg-background.swift
// The icon positions must match release.sh: app at x 180, Applications at
// x 480, both at y 190 (from the top of the window).
import AppKit

let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let size = NSSize(width: 660, height: 400)
let chrome = NSColor(srgbRed: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255, alpha: 1)
let text = NSColor(srgbRed: 0xC8 / 255, green: 0xC8 / 255, blue: 0xC8 / 255, alpha: 1)
let quiet = NSColor(srgbRed: 0x80 / 255, green: 0x80 / 255, blue: 0x80 / 255, alpha: 1)
let accent = NSColor(srgbRed: 0xC0 / 255, green: 0x6A / 255, blue: 0x2B / 255, alpha: 1)

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // AppKit draws bottom-up; `top` converts the Finder window's y (from the top).
    func top(_ y: CGFloat) -> CGFloat { size.height - y }

    chrome.setFill()
    NSRect(origin: .zero, size: size).fill()

    // Arrow between the two icons.
    let arrow = NSBezierPath()
    arrow.lineWidth = 2
    arrow.lineCapStyle = .round
    arrow.move(to: NSPoint(x: 280, y: top(190)))
    arrow.line(to: NSPoint(x: 380, y: top(190)))
    arrow.move(to: NSPoint(x: 368, y: top(178)))
    arrow.line(to: NSPoint(x: 380, y: top(190)))
    arrow.line(to: NSPoint(x: 368, y: top(202)))
    accent.setStroke()
    arrow.stroke()

    func draw(_ string: String, font: NSFont, color: NSColor, kern: CGFloat = 0, centerY: CGFloat) {
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern])
        let bounds = attributed.size()
        attributed.draw(at: NSPoint(x: (size.width - bounds.width) / 2, y: top(centerY) - bounds.height / 2))
    }
    draw("Arraste o Cadex para Aplicativos", font: .systemFont(ofSize: 14), color: text, centerY: 316)
    draw("CADEX · TERMINAL E WORKSPACE", font: .monospacedSystemFont(ofSize: 10, weight: .medium), color: quiet, kern: 0.8, centerY: 44)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let image = NSImage(size: size)
image.addRepresentation(render(scale: 1))
image.addRepresentation(render(scale: 2))
try! image.tiffRepresentation(using: .lzw, factor: 0)!.write(to: folder.appendingPathComponent("dmg-background.tiff"))
print(folder.appendingPathComponent("dmg-background.tiff").path)
