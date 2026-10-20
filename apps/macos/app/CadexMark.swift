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

    /// While on, a flame rises from the top of the > (owner, 2026-10-20):
    /// the fill weight's fire-simple, this tall.
    static let flameSize: CGFloat = 7
    /// Room above the logo for the flame, in both states, so the logo
    /// does not move when it turns on.
    static let flameRoom: CGFloat = 4

    static func image(on: Bool, height: CGFloat = 14) -> NSImage {
        let scale = height / box.height
        let size = NSSize(width: ceil(box.width * scale) + 2, height: height + 2 + flameRoom)
        let flame = on ? Icon.fireSimple.image(size: flameSize, filled: true) : nil
        let image = NSImage(size: size, flipped: true) { _ in
            var transform = AffineTransform(translationByX: 1 - box.minX * scale, byY: 1 + flameRoom - box.minY * scale)
            transform.scale(scale)
            NSColor.black.withAlphaComponent(on ? 1 : offAlpha).setFill()
            for path in paths() {
                path.transform(using: transform)
                path.fill()
            }
            if let flame {
                // On the >'s upper arm (x 795, y 540 in the SVG), right
                // enough to clear the C's top end (x 647): centered on the
                // >, it merged with the C.
                let center = 1 + (795 - box.minX) * scale
                let foot = 1 + flameRoom + (540 - box.minY) * scale
                flame.draw(in: NSRect(x: center - flameSize / 2, y: foot - flameSize, width: flameSize, height: flameSize),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
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
