//! Dates in Portuguese, as the Mac shows them whatever the system's
//! language (HistoryRows.swift, pt_BR): "há 3 horas" in the list and
//! "17 de outubro de 2026 às 14:05" in the details, in local time.

const std = @import("std");
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

/// "há 3 horas", "há 1 dia", "agora": the largest unit, as
/// RelativeDateTimeFormatter's full style.
pub fn relative(buf: []u8, now: i64, then: i64) []const u8 {
    const ago = now - then;
    if (ago < 1) return "agora";
    const units = [_]struct { seconds: i64, one: []const u8, many: []const u8 }{
        .{ .seconds = 365 * 86_400, .one = "ano", .many = "anos" },
        .{ .seconds = 30 * 86_400, .one = "mês", .many = "meses" },
        .{ .seconds = 7 * 86_400, .one = "semana", .many = "semanas" },
        .{ .seconds = 86_400, .one = "dia", .many = "dias" },
        .{ .seconds = 3600, .one = "hora", .many = "horas" },
        .{ .seconds = 60, .one = "minuto", .many = "minutos" },
        .{ .seconds = 1, .one = "segundo", .many = "segundos" },
    };
    for (units) |u| {
        if (ago < u.seconds) continue;
        const n = @divTrunc(ago, u.seconds);
        return std.fmt.bufPrint(buf, "há {d} {s}", .{ n, if (n == 1) u.one else u.many }) catch "";
    }
    return "agora";
}

const months = [_][]const u8{ "janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro" };

/// "17 de outubro de 2026 às 14:05".
pub fn formatLong(buf: []u8, day: u16, month: u16, year: u16, hour: u16, minute: u16) []const u8 {
    const name = months[@min(@max(month, 1), 12) - 1];
    return std.fmt.bufPrint(buf, "{d} de {s} de {d} às {d:0>2}:{d:0>2}", .{ day, name, year, hour, minute }) catch "";
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
    try std.testing.expectEqualStrings("agora", relative(&buf, 100, 100));
    try std.testing.expectEqualStrings("há 1 minuto", relative(&buf, 160, 100));
    try std.testing.expectEqualStrings("há 3 horas", relative(&buf, 3 * 3600 + 5, 0));
    try std.testing.expectEqualStrings("há 2 meses", relative(&buf, 61 * 86_400, 0));
    try std.testing.expectEqualStrings("há 1 ano", relative(&buf, 400 * 86_400, 0));
}

test "the long date reads like the Mac's" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("17 de outubro de 2026 às 09:05", formatLong(&buf, 17, 10, 2026, 9, 5));
}

test {
    @import("win32").refAllDeep(@This());
}
