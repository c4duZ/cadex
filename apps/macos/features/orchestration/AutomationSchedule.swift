import Foundation
import Strings

/// When an automation runs (docs/spec/orchestration.md "Automações",
/// docs/adr/0034-scheduled-automations.md; plan 24 E), pure: the next time
/// after a date, what is due now (on time, missed while the Mac slept or
/// Cadex was closed, or skipped because the last run still goes), and the
/// dates the launchd job wakes the app at. No clock of its own.
public enum AutomationSchedule {
    /// What to do with an automation now.
    public enum Due: Equatable, Sendable {
        case nothing
        /// Run it, for the time it was due.
        case run(Date)
        /// Record a skipped run for that time, with why ("missed", "still running").
        case skip(Date, String)
    }

    /// Late by more than this, a time counts as missed: the job fires on the
    /// minute and the app answers within seconds; two minutes covers a
    /// slow launch of the app it opened.
    public static let grace: TimeInterval = 120

    /// The first time strictly after `date`; nil for a once that passed.
    public static func next(_ recurrence: Recurrence, after date: Date, calendar: Calendar = .current) -> Date? {
        switch recurrence {
        case .once(let at): return at > date ? at : nil
        case .daily(let hour, let minute):
            return calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute, second: 0), matchingPolicy: .nextTime)
        case .weekdays(let hour, let minute):
            var candidate = date
            for _ in 0..<8 {
                guard let found = calendar.nextDate(after: candidate, matching: DateComponents(hour: hour, minute: minute, second: 0),
                                                    matchingPolicy: .nextTime) else { return nil }
                let weekday = calendar.component(.weekday, from: found)
                if (2...6).contains(weekday) { return found }
                candidate = found
            }
            return nil
        case .everyHours(let n):
            return stepping(after: date, by: .hour, every: max(1, n), calendar: calendar)
        case .everyMinutes(let n):
            return stepping(after: date, by: .minute, every: max(1, n), calendar: calendar)
        }
    }

    /// Every n hours from midnight (0:00, 4:00, 8:00…), or every n minutes
    /// from the hour (:00, :02…): the same times the launchd job fires.
    static func stepping(after date: Date, by unit: Calendar.Component, every n: Int, calendar: Calendar) -> Date? {
        let start = unit == .hour ? calendar.startOfDay(for: date)
            : calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: date)) ?? date
        var candidate = start
        while candidate <= date {
            guard let later = calendar.date(byAdding: unit, value: n, to: candidate) else { return nil }
            candidate = later
        }
        // An uneven step (every 7 h) starts again at the next day or hour,
        // as the launchd dates do.
        let boundary = unit == .hour ? calendar.date(byAdding: .day, value: 1, to: start) : calendar.date(byAdding: .hour, value: 1, to: start)
        if let boundary, candidate > boundary { return boundary }
        return candidate
    }

    /// What is due at `now`: the latest time after the last run (or after
    /// it was turned on) that is not in the future. Several missed become
    /// one. Late past `grace`, it is a missed run: run once, or skip, as
    /// the automation says. A run still going makes the new one "still running".
    public static func due(_ automation: Automation, lastScheduled: Date?, running: Bool, now: Date, calendar: Calendar = .current) -> Due {
        guard automation.enabled, let since = [lastScheduled, automation.enabledAt].compactMap({ $0 }).max() else { return .nothing }
        var latest: Date?
        var cursor = since
        // At most a year of every-minute times: never loops forever.
        for _ in 0..<600_000 {
            guard let found = next(automation.recurrence, after: cursor, calendar: calendar), found <= now else { break }
            latest = found
            cursor = found
        }
        guard let time = latest else { return .nothing }
        if running { return .skip(time, "still running") }
        if now.timeIntervalSince(time) > grace, automation.missed == .skip { return .skip(time, "missed") }
        return .run(time)
    }

    /// The launchd job's StartCalendarInterval entries for a recurrence
    /// (keys Minute, Hour, Day, Month, Weekday; launchd's Sunday is 0).
    public static func launchdDates(_ recurrence: Recurrence, calendar: Calendar = .current) -> [[String: Int]] {
        switch recurrence {
        case .daily(let hour, let minute): return [["Hour": hour, "Minute": minute]]
        case .weekdays(let hour, let minute): return (1...5).map { ["Weekday": $0, "Hour": hour, "Minute": minute] }
        case .everyHours(let n): return stride(from: 0, to: 24, by: max(1, n)).map { ["Hour": $0, "Minute": 0] }
        case .everyMinutes(let n): return stride(from: 0, to: 60, by: max(1, n)).map { ["Minute": $0] }
        case .once(let at):
            let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: at)
            return [["Month": parts.month ?? 1, "Day": parts.day ?? 1, "Hour": parts.hour ?? 0, "Minute": parts.minute ?? 0]]
        }
    }

    /// "Weekdays at 09:00", "Every 4 hours"… for the form and the lists.
    public static func label(_ recurrence: Recurrence) -> String {
        let f = { (h: Int, m: Int) in String(format: "%02d:%02d", h, m) }
        switch recurrence {
        case .weekdays(let h, let m): return T("Weekdays at \(f(h, m))", "Dias úteis às \(f(h, m))")
        case .daily(let h, let m): return T("Every day at \(f(h, m))", "Todo dia às \(f(h, m))")
        case .everyHours(let n): return n == 1 ? T("Every hour", "A cada hora") : T("Every \(n) hours", "A cada \(n) horas")
        case .everyMinutes(let n): return n == 1 ? T("Every minute", "A cada minuto") : T("Every \(n) minutes", "A cada \(n) minutos")
        case .once(let at): return T("Once, ", "Uma vez, ") + at.formatted(date: .abbreviated, time: .shortened)
        }
    }
}
