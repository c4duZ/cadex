import AppKit
import Icons

/// The Cadex symbol (the C, the > and the _ of docs/cadex-icon.svg) as a
/// template image for the menu bar, always filled like the logo: full
/// while on, faint (gray on a dark bar) while off. The outline for off
/// looked thin and odd (owner, 2026-10-20). The paths are the SVG's, in
/// its 1254-unit space.
@MainActor
enum CadexMark {
    /// The symbol's box in the SVG: x 280...964, y 337...902.
    private static let box = NSRect(x: 280, y: 337, width: 684, height: 565)

    /// How much of the color the off state keeps: templates keep alpha.
    static let offAlpha: CGFloat = 0.4

    /// While on, a flame rises from the top right, over the _ (owner,
    /// 2026-10-20): the fill weight's fire-simple, this tall.
    static let flameSize: CGFloat = 8

    static func image(on: Bool, height: CGFloat = 15) -> NSImage {
        let scale = height / box.height
        let logoWidth = ceil(box.width * scale) + 2
        // Right of the >'s tip, with a point of air, so the two do not merge.
        let flameX = (825 - box.minX) * scale + 2
        let size = NSSize(width: max(logoWidth, on ? ceil(flameX + flameSize) + 1 : 0), height: height + 2)
        let flame = on ? Icon.fireSimple.image(size: flameSize, filled: true) : nil
        let image = NSImage(size: size, flipped: true) { _ in
            if let flame {
                // Its foot on the _'s top edge, rising out of it.
                let underscoreTop = (804 - box.minY) * scale + 1
                let rect = NSRect(x: flameX, y: underscoreTop - flameSize + 0.5, width: flameSize, height: flameSize)
                flame.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            var transform = AffineTransform(translationByX: 1 - box.minX * scale, byY: 1 - box.minY * scale)
            transform.scale(scale)
            NSColor.black.withAlphaComponent(on ? 1 : offAlpha).setFill()
            for path in paths() {
                path.transform(using: transform)
                path.fill()
            }
            return true
        }
        // The menu bar paints templates in its own color, light or dark.
        image.isTemplate = true
        return image
    }

    private static func paths() -> [NSBezierPath] {
        let c = NSBezierPath()
        c.move(to: NSPoint(x: 587, y: 337))
        c.curve(to: NSPoint(x: 280, y: 591), controlPoint1: NSPoint(x: 455, y: 333), controlPoint2: NSPoint(x: 285, y: 447))
        c.curve(to: NSPoint(x: 582, y: 901), controlPoint1: NSPoint(x: 273, y: 745), controlPoint2: NSPoint(x: 402, y: 901))
        c.line(to: NSPoint(x: 647, y: 805))
        c.line(to: NSPoint(x: 574, y: 805))
        c.curve(to: NSPoint(x: 378, y: 618), controlPoint1: NSPoint(x: 464, y: 806), controlPoint2: NSPoint(x: 379, y: 723))
        c.curve(to: NSPoint(x: 574, y: 431), controlPoint1: NSPoint(x: 378, y: 518), controlPoint2: NSPoint(x: 456, y: 433))
        c.line(to: NSPoint(x: 647, y: 437))
        c.curve(to: NSPoint(x: 587, y: 337), controlPoint1: NSPoint(x: 619, y: 401), controlPoint2: NSPoint(x: 600, y: 365))
        c.close()
        let chevron = NSBezierPath()
        let points = [(668, 462), (825, 623), (669, 780), (608, 719), (713, 623), (608, 524)].map { NSPoint(x: $0.0, y: $0.1) }
        chevron.move(to: points[0])
        points.dropFirst().forEach { chevron.line(to: $0) }
        chevron.close()
        let underscore = NSBezierPath(rect: NSRect(x: 748, y: 804, width: 216, height: 98))
        return [c, chevron, underscore]
    }
}
