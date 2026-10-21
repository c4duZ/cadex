import AppKit
import Icons
import UserNotifications

/// The picture beside a notification's text, one per kind of stop: a lock
/// with a key (permission), a question mark (question), a check (finished),
/// white on a rounded square in the theme's accent. macOS keeps the app's
/// icon on the left of every notification and lets no app change it; an
/// attachment shows on the right (the owner asked for an icon per kind,
/// 2026-10-21). Drawn once per kind and accent, kept in the app's caches.
@MainActor
enum AgentNotifyIcon {
    static func icon(for stop: AgentStop) -> Icon {
        switch stop {
        case .permission: .lockKey
        case .question, .unknown: .question
        case .finished, .interrupted: .checkCircle
        }
    }

    /// The attachment for `stop`, nil if the picture could not be written.
    static func attachment(for stop: AgentStop, accent: NSColor) -> UNNotificationAttachment? {
        guard let url = file(for: icon(for: stop), accent: accent) else { return nil }
        return try? UNNotificationAttachment(identifier: url.lastPathComponent, url: url, options: nil)
    }

    /// The PNG, drawn the first time. The system moves an attachment into
    /// its own store, so each post gets a fresh copy of the cached file.
    static func file(for icon: Icon, accent: NSColor) -> URL? {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Cadex").appendingPathComponent("notification-icons")
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let rgb = accent.usingColorSpace(.sRGB) ?? accent
        let name = String(format: "%X-%02X%02X%02X", icon.rawValue, Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
        let kept = caches.appendingPathComponent(name + ".png")
        if !FileManager.default.fileExists(atPath: kept.path) {
            guard let png = draw(icon, accent: rgb) else { return nil }
            try? png.write(to: kept)
        }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("cadex-notify-\(UUID().uuidString).png")
        guard (try? FileManager.default.copyItem(at: kept, to: copy)) != nil else { return nil }
        return copy
    }

    static func draw(_ icon: Icon, accent: NSColor) -> Data? {
        let side: CGFloat = 128
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            accent.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 28, yRadius: 28).fill()
            let glyph = icon.image(size: 76, filled: true)
            let tinted = NSImage(size: glyph.size, flipped: false) { r in
                glyph.draw(in: r)
                NSColor.white.set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: (side - 76) / 2, y: (side - 76) / 2, width: 76, height: 76))
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
