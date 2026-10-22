import AppKit
import Icons
import UserNotifications

/// The picture beside a notification's text: Cadex's own icon with a badge
/// in its corner, one per kind of stop: a lock (permission, amber), a
/// question mark (question, blue), a check (finished, green). macOS keeps
/// the app's icon on the left of every notification and lets no app change
/// it; an attachment shows on the right. A white glyph on a square of the
/// theme's accent looked out of place there; variations of the app's icon
/// read as Cadex (the owner, 2026-10-22). Drawn once per kind, kept in the
/// app's caches.
@MainActor
enum AgentNotifyIcon {
    static func icon(for stop: AgentStop) -> Icon {
        switch stop {
        case .permission: .lockKey
        case .question, .unknown: .questionMark
        case .finished, .interrupted: .check
        }
    }

    /// The badge's color for each kind.
    static func color(for icon: Icon) -> NSColor {
        switch icon {
        case .lockKey: NSColor(srgbRed: 0.96, green: 0.62, blue: 0.04, alpha: 1)
        case .questionMark: NSColor(srgbRed: 0.23, green: 0.51, blue: 0.96, alpha: 1)
        default: NSColor(srgbRed: 0.13, green: 0.77, blue: 0.37, alpha: 1)
        }
    }

    /// The app's icon; the tests set the one from docs/, as a test runs
    /// outside the app's bundle.
    static var appIcon: () -> NSImage = { NSApp.applicationIconImage ?? NSImage() }

    /// The attachment for `stop`, nil if the picture could not be written.
    static func attachment(for stop: AgentStop) -> UNNotificationAttachment? {
        guard let url = file(for: icon(for: stop)) else { return nil }
        return try? UNNotificationAttachment(identifier: url.lastPathComponent, url: url, options: nil)
    }

    /// The PNG, drawn the first time. The system moves an attachment into
    /// its own store, so each post gets a fresh copy of the cached file.
    static func file(for icon: Icon) -> URL? {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Cadex").appendingPathComponent("notification-icons")
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let kept = caches.appendingPathComponent(String(format: "badge-%X.png", icon.rawValue))
        if !FileManager.default.fileExists(atPath: kept.path) {
            guard let png = draw(icon) else { return nil }
            try? png.write(to: kept)
        }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("cadex-notify-\(UUID().uuidString).png")
        guard (try? FileManager.default.copyItem(at: kept, to: copy)) != nil else { return nil }
        return copy
    }

    /// The icon at 256 px with the badge over its bottom right corner: a
    /// circle in the kind's color, a ring of the icon's dark ground around
    /// it, the glyph in white.
    static func draw(_ icon: Icon) -> Data? {
        let side: CGFloat = 256
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            appIcon().draw(in: rect)
            let badge = NSRect(x: side * 0.56, y: side * 0.04, width: side * 0.40, height: side * 0.40)
            NSColor(srgbRed: 0.09, green: 0.11, blue: 0.14, alpha: 1).setFill()
            NSBezierPath(ovalIn: badge.insetBy(dx: -side * 0.025, dy: -side * 0.025)).fill()
            color(for: icon).setFill()
            NSBezierPath(ovalIn: badge).fill()
            let glyphSide = badge.width * 0.62
            let glyph = icon.fittedImage(size: glyphSide)
            let tinted = NSImage(size: glyph.size, flipped: false) { r in
                glyph.draw(in: r)
                NSColor.white.set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: badge.midX - glyphSide / 2, y: badge.midY - glyphSide / 2, width: glyphSide, height: glyphSide))
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
