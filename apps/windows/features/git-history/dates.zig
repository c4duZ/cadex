//! Dates in the interface's language, as the Mac shows them whatever the
//! system's (HistoryRows.swift, en_US or pt_BR): "3 hours ago" or "há 3
//! horas" in the list and "October 17, 2026 at 2:05 PM" or "17 de outubro
//! de 2026 às 14:05" in the details, in local time.

const std = @import("std");
const strings = @import("strings");
const w = @import("win32");
const c = w.c;

/// Seconds since 1970, now (the system clock, UTC).
pub fn nowUnix() i64 {
    var ft: c.FILETIME = undefined;
    c.GetSystemTimeAsFileTime(&ft);
    const ticks = (@as(u64, ft.dwHighDateTime) << 32) | ft.dwLowDateTime;
    return @as(i64, @intCast(ticks / 10_000_000)) - epoch_gap;
}

/// From 1601 (FILETIME's start) to 1970, in seconds.
const epoch_gap: i64 = 11_644_473_600;

/// "3 hours ago", "1 day ago", "now" ("há 3 horas", "há 1 dia", "agora"):
/// the largest unit, as RelativeDateTimeFormatter's full style.
pub fn relative(buf: []u8, now: i64, then: i64) []const u8 {
    const pt = strings.language == .pt;
    const ago = now - then;
    if (ago < 1) return if (pt) "agora" else "now";
    // Each unit's singular and plural, English then Portuguese.
    const units = [_]struct { seconds: i64, en: [2][]const u8, pt: [2][]const u8 }{
        .{ .seconds = 365 * 86_400, .en = .{ "year", "years" }, .pt = .{ "ano", "anos" } },
        .{ .seconds = 30 * 86_400, .en = .{ "month", "months" }, .pt = .{ "mês", "meses" } },
        .{ .seconds = 7 * 86_400, .en = .{ "week", "weeks" }, .pt = .{ "semana", "semanas" } },
        .{ .seconds = 86_400, .en = .{ "day", "days" }, .pt = .{ "dia", "dias" } },
        .{ .seconds = 3600, .en = .{ "hour", "hours" }, .pt = .{ "hora", "horas" } },
        .{ .seconds = 60, .en = .{ "minute", "minutes" }, .pt = .{ "minuto", "minutos" } },
        .{ .seconds = 1, .en = .{ "second", "seconds" }, .pt = .{ "segundo", "segundos" } },
    };
    for (units) |u| {
        if (ago < u.seconds) continue;
        const n = @divTrunc(ago, u.seconds);
        const names = if (pt) u.pt else u.en;
        const name = names[if (n == 1) 0 else 1];
        if (pt) return std.fmt.bufPrint(buf, "há {d} {s}", .{ n, name }) catch "";
        return std.fmt.bufPrint(buf, "{d} {s} ago", .{ n, name }) catch "";
    }
    return if (pt) "agora" else "now";
}

const months_en = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
const months_pt = [_][]const u8{ "janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro" };

/// "October 17, 2026 at 2:05 PM" (en_US) or "17 de outubro de 2026 às
/// 14:05" (pt_BR), DateFormatter's long date and short time.
pub fn formatLong(buf: []u8, day: u16, month: u16, year: u16, hour: u16, minute: u16) []const u8 {
    const m = @min(@max(month, 1), 12) - 1;
    if (strings.language == .pt) {
        return std.fmt.bufPrint(buf, "{d} de {s} de {d} às {d:0>2}:{d:0>2}", .{ day, months_pt[m], year, hour, minute }) catch "";
    }
    const h12 = if (hour % 12 == 0) 12 else hour % 12;
    const half = if (hour < 12) "AM" else "PM";
    return std.fmt.bufPrint(buf, "{s} {d}, {d} at {d}:{d:0>2} {s}", .{ months_en[m], day, year, h12, minute, half }) catch "";
}

/// The long date of a unix time, in the system's time zone.
pub fn full(buf: []u8, unix: i64) []const u8 {
    const ticks: u64 = @intCast(@max(unix + epoch_gap, 0) * 10_000_000);
    const utc: c.FILETIME = .{ .dwLowDateTime = @truncate(ticks), .dwHighDateTime = @truncate(ticks >> 32) };
    var local: c.FILETIME = undefined;
    var st: c.SYSTEMTIME = undefined;
    if (c.FileTimeToLocalFileTime(&utc, &local) == 0 or c.FileTimeToSystemTime(&local, &st) == 0) return "";
    return formatLong(buf, st.wDay, st.wMonth, st.wYear, st.wHour, st.wMinute);
}

test "relative dates take the largest unit, singular and plural" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("now", relative(&buf, 100, 100));
    try std.testing.expectEqualStrings("1 minute ago", relative(&buf, 160, 100));
    try std.testing.expectEqualStrings("3 hours ago", relative(&buf, 3 * 3600 + 5, 0));
    try std.testing.expectEqualStrings("1 year ago", relative(&buf, 400 * 86_400, 0));
    strings.language = .pt;
    defer strings.language = .en;
    try std.testing.expectEqualStrings("agora", relative(&buf, 100, 100));
    try std.testing.expectEqualStrings("há 1 minuto", relative(&buf, 160, 100));
    try std.testing.expectEqualStrings("há 3 horas", relative(&buf, 3 * 3600 + 5, 0));
    try std.testing.expectEqualStrings("há 2 meses", relative(&buf, 61 * 86_400, 0));
    try std.testing.expectEqualStrings("há 1 ano", relative(&buf, 400 * 86_400, 0));
}

test "the long date reads like the Mac's" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("October 17, 2026 at 9:05 AM", formatLong(&buf, 17, 10, 2026, 9, 5));
    try std.testing.expectEqualStrings("October 17, 2026 at 12:30 PM", formatLong(&buf, 17, 10, 2026, 12, 30));
    strings.language = .pt;
    defer strings.language = .en;
    try std.testing.expectEqualStrings("17 de outubro de 2026 às 09:05", formatLong(&buf, 17, 10, 2026, 9, 5));
}

test {
    @import("win32").refAllDeep(@This());
}
