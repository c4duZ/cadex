import AppKit

/// The Cadex symbol (the C, the > and the _ of docs/cadex-icon.svg) as a
/// template image for the menu bar: filled, like the logo, or only its
/// outline. The paths are the SVG's, in its 1254-unit space.
enum CadexMark {
    /// The symbol's box in the SVG: x 280...964, y 337...902.
    private static let box = NSRect(x: 280, y: 337, width: 684, height: 565)

    static func image(filled: Bool, height: CGFloat = 15) -> NSImage {
        let scale = height / box.height
        let size = NSSize(width: ceil(box.width * scale) + 2, height: height + 2)
        let image = NSImage(size: size, flipped: true) { _ in
            var transform = AffineTransform(translationByX: 1 - box.minX * scale, byY: 1 - box.minY * scale)
            transform.scale(scale)
            NSColor.black.set()
            for path in paths() {
                path.transform(using: transform)
                if filled {
                    path.fill()
                } else {
                    path.lineWidth = 1.2
                    path.lineJoinStyle = .miter
                    path.stroke()
                }
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
