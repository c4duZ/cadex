import Foundation
import UserNotifications

/// Each kind of notification plays its own sound, chosen in the settings
/// (agents.soundPermission, -Question, -Finished; the owner, 2026-10-22: all
/// three sound, each one his). The system plays it with the notification,
/// so Focus and the Cadex switch in System Settings › Notifications still
/// rule: a sound file is named, and macOS looks for it in ~/Library/Sounds
/// for an app outside a sandbox. The chosen file is copied there as
/// "Cadex Permission.aiff" (and Question, Finished), the one place it can
/// be named from.
enum AgentNotifySound {
    static let systemFolder = "/System/Library/Sounds"

    /// "none": silent; "default": the system's alert; a name of a macOS
    /// sound ("Glass"); or the path of a file of yours (.aiff, .wav, .caf).
    static func sound(_ value: String, kind: AgentNotifyText.Kind, home: String = NSHomeDirectory()) -> UNNotificationSound? {
        switch value {
        case "none": return nil
        case "", "default": return .default
        default:
            guard let source = file(value), let name = install(source, kind: kind, home: home) else { return .default }
            return UNNotificationSound(named: UNNotificationSoundName(name))
        }
    }

    /// The file a value names, if it is there.
    static func file(_ value: String) -> String? {
        let path = value.hasPrefix("/") ? value : systemFolder + "/" + value + ".aiff"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// Copies `source` to ~/Library/Sounds under the kind's name, unless the
    /// same file is already there; the name to give the notification.
    static func install(_ source: String, kind: AgentNotifyText.Kind, home: String) -> String? {
        let folder = home + "/Library/Sounds"
        let name = "Cadex " + kind.rawValue.capitalized + "." + (source as NSString).pathExtension.lowercased()
        let target = folder + "/" + name
        let files = FileManager.default
        if files.contentsEqual(atPath: source, andPath: target) { return name }
        try? files.createDirectory(atPath: folder, withIntermediateDirectories: true)
        // Other extensions of the same kind would be found first by name.
        for old in (try? files.contentsOfDirectory(atPath: folder)) ?? [] where old.hasPrefix("Cadex " + kind.rawValue.capitalized + ".") {
            try? files.removeItem(atPath: folder + "/" + old)
        }
        return (try? files.copyItem(atPath: source, toPath: target)) != nil ? name : nil
    }
}
