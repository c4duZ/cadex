import AppKit
import Strings
import UILooks

/// "16:30" today, "Oct 28" another day.
public enum AgentResetTime {
    /// "3 days ago".
    public static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: Strings.language == .pt ? "pt_BR" : "en_US")
        return f.localizedString(for: date, relativeTo: Date())
    }

    public static func text(_ date: Date, now: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Strings.language == .pt ? "pt_BR" : "en_US")
        if Calendar.current.isDate(date, inSameDayAs: now) {
            f.dateStyle = .none
            f.timeStyle = .short
        } else {
            f.setLocalizedDateFormatFromTemplate("MMM d")
        }
        return f.string(from: date)
    }
}
