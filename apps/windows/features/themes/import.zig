//! Reads the terminal theme files other apps use (plan 15, phase A), as the
//! Mac's ThemeImport.swift: iTerm2's .itermcolors, a Ghostty theme, a
//! base16 or base24 scheme (.yaml), or a Cadex theme (.json). The
//! interface colors of a terminal theme are made from its own background,
//! text and blue, with the Mac's numbers, so an import looks the same on
//! both machines.

const std = @import("std");
const t = @import("strings").t;
const theme = @import("theme.zig");
const file = @import("file.zig");

const Theme = theme.Theme;
const Problem = theme.Problem;
const Error = theme.Error;

/// Reads `data`, the file `path` (its extension says the format; its name
/// without the extension names the theme when the file has no name).
/// Strings go in `arena`; `gpa` holds what is parsed meanwhile.
pub fn read(arena: std.mem.Allocator, gpa: std.mem.Allocator, path: []const u8, data: []const u8, problem: *Problem) Error!Theme {
    const base = path[if (std.mem.lastIndexOfAny(u8, path, "/\\")) |i| i + 1 else 0..];
    const dot = std.mem.lastIndexOfScalar(u8, base, '.');
    const stem = if (dot) |d| (if (d > 0) base[0..d] else base) else base;
    const ext = if (dot) |d| base[d + 1 ..] else "";
    const name = arena.dupe(u8, stem) catch return error.InvalidTheme;
    if (std.ascii.eqlIgnoreCase(ext, "json")) return file.read(arena, gpa, data, problem);
    if (std.ascii.eqlIgnoreCase(ext, "itermcolors")) return iterm(data, name, problem);
    if (std.ascii.eqlIgnoreCase(ext, "yaml") or std.ascii.eqlIgnoreCase(ext, "yml")) return base16(arena, data, name, problem);
    return ghostty(data, name, problem);
}

// ---- iTerm2 ----

/// The plist's "<key>Ansi 0 Color</key><dict>...</dict>" entries, each
/// with Red, Green and Blue Component reals from 0 to 1.
fn iterm(data: []const u8, name: []const u8, problem: *Problem) Error!Theme {
    if (std.mem.indexOf(u8, data, "<plist") == null) return fail(problem, "(file)", t("not an .itermcolors", "não é um .itermcolors"));
    var ansi: [16]u32 = undefined;
    var key_buf: [32]u8 = undefined;
    for (&ansi, 0..) |*a, i| {
        const key = std.fmt.bufPrint(&key_buf, "Ansi {d} Color", .{i}) catch unreachable;
        a.* = itermColor(data, key) orelse return fail(problem, "Ansi Color", t("missing color", "falta a cor"));
    }
    const background = itermColor(data, "Background Color") orelse return fail(problem, "Background Color", t("missing color", "falta a cor"));
    const foreground = itermColor(data, "Foreground Color") orelse return fail(problem, "Foreground Color", t("missing color", "falta a cor"));
    return derived(name, .{
        .background = background,
        .foreground = foreground,
        .cursor = itermColor(data, "Cursor Color") orelse foreground,
        .selection = itermColor(data, "Selection Color") orelse theme.mix(background, foreground, 0.25),
        .ansi = ansi,
    });
}

fn itermColor(data: []const u8, key: []const u8) ?u32 {
    const dict = itermDict(data, key) orelse return null;
    return channel(dict, "Red Component") << 16 | channel(dict, "Green Component") << 8 | channel(dict, "Blue Component");
}

/// The text between the <dict> after <key>`key`</key> and its </dict>.
fn itermDict(data: []const u8, key: []const u8) ?[]const u8 {
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, data, at, "<key>")) |start| {
        const open = start + "<key>".len;
        const close = std.mem.indexOfPos(u8, data, open, "</key>") orelse return null;
        at = close;
        if (!std.mem.eql(u8, std.mem.trim(u8, data[open..close], " \t\r\n"), key)) continue;
        const rest = std.mem.trimStart(u8, data[close + "</key>".len ..], " \t\r\n");
        if (!std.mem.startsWith(u8, rest, "<dict>")) return null;
        const end = std.mem.indexOf(u8, rest, "</dict>") orelse return null;
        return rest["<dict>".len..end];
    }
    return null;
}

/// One component as 0...255; a missing one is 0, as on the Mac.
fn channel(dict: []const u8, key: []const u8) u32 {
    const value = itermValue(dict, key) orelse return 0;
    const number = std.fmt.parseFloat(f64, value) catch return 0;
    return @intFromFloat(std.math.clamp(@round(number * 255), 0, 255));
}

fn itermValue(dict: []const u8, key: []const u8) ?[]const u8 {
    const key_at = std.mem.indexOf(u8, dict, key) orelse return null;
    const after = dict[key_at + key.len ..];
    const open = std.mem.indexOf(u8, after, "</key>") orelse return null;
    const tag_start = std.mem.indexOfScalarPos(u8, after, open + "</key>".len, '<') orelse return null;
    const tag_end = std.mem.indexOfScalarPos(u8, after, tag_start, '>') orelse return null;
    const value_end = std.mem.indexOfScalarPos(u8, after, tag_end, '<') orelse return null;
    return std.mem.trim(u8, after[tag_end + 1 .. value_end], " \t\r\n");
}

// ---- Ghostty ----

/// "key = value" lines; "palette = N=#hex" for the 16 colors.
fn ghostty(data: []const u8, name: []const u8, problem: *Problem) Error!Theme {
    var palette: [16]?[]const u8 = @splat(null);
    var background: ?[]const u8 = null;
    var foreground: ?[]const u8 = null;
    var cursor: ?[]const u8 = null;
    var selection: ?[]const u8 = null;
    var lines = std.mem.tokenizeAny(u8, data, "\r\n");
    while (lines.next()) |line| {
        const key, const value = splitOnce(line, '=') orelse continue;
        if (std.mem.eql(u8, key, "palette")) {
            const index, const color = splitOnce(value, '=') orelse continue;
            const n = std.fmt.parseInt(usize, index, 10) catch continue;
            if (n < 16) palette[n] = color;
        } else if (std.mem.eql(u8, key, "background")) {
            background = value;
        } else if (std.mem.eql(u8, key, "foreground")) {
            foreground = value;
        } else if (std.mem.eql(u8, key, "cursor-color")) {
            cursor = value;
        } else if (std.mem.eql(u8, key, "selection-background")) {
            selection = value;
        }
    }
    var ansi: [16]u32 = undefined;
    for (&ansi, palette) |*a, p| a.* = try hexColor(p, "palette", problem);
    const bg = try hexColor(background, "background", problem);
    const fg = try hexColor(foreground, "foreground", problem);
    return derived(name, .{
        .background = bg,
        .foreground = fg,
        .cursor = optionalColor(cursor) orelse fg,
        .selection = optionalColor(selection) orelse theme.mix(bg, fg, 0.25),
        .ansi = ansi,
    });
}

/// "a = b" as trimmed halves, split at the first `sep`.
fn splitOnce(line: []const u8, sep: u8) ?struct { []const u8, []const u8 } {
    const i = std.mem.indexOfScalar(u8, line, sep) orelse return null;
    return .{ std.mem.trim(u8, line[0..i], " \t"), std.mem.trim(u8, line[i + 1 ..], " \t") };
}

/// A color with or without its "#".
fn hexColor(value: ?[]const u8, field: []const u8, problem: *Problem) Error!u32 {
    const v = value orelse return fail(problem, field, t("missing color", "falta a cor"));
    var buf: [16]u8 = undefined;
    const text = if (std.mem.startsWith(u8, v, "#")) v else std.fmt.bufPrint(&buf, "#{s}", .{v}) catch return fail(problem, field, t("not a #RRGGBB color", "não é uma cor #RRGGBB"));
    return theme.parseColor(text) catch fail(problem, field, t("not a #RRGGBB color", "não é uma cor #RRGGBB"));
}

/// A color that may be missing or wrong: the caller has a fallback.
fn optionalColor(value: ?[]const u8) ?u32 {
    var ignored: Problem = .{};
    return hexColor(value, "", &ignored) catch null;
}

// ---- base16 and base24 ----

/// tinted-theming's terminal mapping, as tools/themes/tinted.py does.
fn base16(arena: std.mem.Allocator, data: []const u8, fallback: []const u8, problem: *Problem) Error!Theme {
    var keys: [24]?[]const u8 = @splat(null);
    var name = fallback;
    var lines = std.mem.tokenizeAny(u8, data, "\r\n");
    while (lines.next()) |line| {
        const key, const raw = splitOnce(line, ':') orelse continue;
        const clean = withoutQuotes(arena, raw) catch return error.InvalidTheme;
        if (std.mem.eql(u8, key, "name")) name = clean;
        const slot = baseSlot(key) orelse continue;
        var words = std.mem.tokenizeScalar(u8, clean, ' ');
        keys[slot] = words.next();
    }
    const normal = [_]usize{ 0x00, 0x08, 0x0B, 0x0A, 0x0D, 0x0E, 0x0C, 0x05 };
    const bright = [_][2]usize{ .{ 0x12, 0x08 }, .{ 0x14, 0x0B }, .{ 0x13, 0x0A }, .{ 0x16, 0x0D }, .{ 0x17, 0x0E }, .{ 0x15, 0x0C } };
    var ansi: [16]u32 = undefined;
    for (normal, 0..) |slot, i| ansi[i] = try baseColor(keys, slot, null, problem);
    ansi[8] = try baseColor(keys, 0x03, null, problem);
    for (bright, 9..) |pair, i| ansi[i] = try baseColor(keys, pair[0], pair[1], problem);
    ansi[15] = try baseColor(keys, 0x07, null, problem);
    return derived(name, .{ .background = ansi[0], .foreground = ansi[7], .cursor = ansi[7], .selection = try baseColor(keys, 0x02, null, problem), .ansi = ansi });
}

/// "base0B" is slot 0x0B; base24 goes to "base17".
fn baseSlot(key: []const u8) ?usize {
    if (key.len != 6 or !std.mem.startsWith(u8, key, "base")) return null;
    const n = std.fmt.parseInt(usize, key[4..], 16) catch return null;
    // The Mac's keys are exact ("base0B"): a lowercase "base0b" is not one.
    if (std.mem.indexOfAny(u8, key[4..], "abcdef") != null or n >= 24) return null;
    return n;
}

fn baseColor(keys: [24]?[]const u8, slot: usize, other: ?usize, problem: *Problem) Error!u32 {
    const value = keys[slot] orelse if (other) |o| keys[o] else null;
    return hexColor(value, "base", problem);
}

fn withoutQuotes(arena: std.mem.Allocator, text: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, text, '"') == null) return text;
    const out = try arena.alloc(u8, text.len - std.mem.count(u8, text, "\""));
    var n: usize = 0;
    for (text) |ch| if (ch != '"') {
        out[n] = ch;
        n += 1;
    };
    return out;
}

// ---- The interface of a terminal theme ----

/// Panels in its background, the frame a little toward its text, the
/// accent its blue (the Mac's numbers).
pub fn derived(name: []const u8, terminal: theme.Terminal) Theme {
    const bg = terminal.background;
    const fg = terminal.foreground;
    const chrome = theme.mix(bg, fg, 0.07);
    const accent = terminal.ansi[4];
    return .{
        .name = name,
        .dark = theme.luminance(bg) < 0.18,
        .interface = .{
            .chrome = chrome,
            .panel = bg,
            .panel_border = theme.mix(bg, fg, 0.14),
            .tab_active = theme.mix(chrome, accent, 0.22),
            .field = theme.mix(bg, fg, 0.1),
            .text = fg,
            .secondary_text = theme.mix(fg, bg, 0.35),
            .accent = accent,
        },
        .terminal = terminal,
    };
}

fn fail(problem: *Problem, field: []const u8, message: []const u8) Error {
    problem.* = .{ .field = field, .message = message };
    return error.InvalidTheme;
}

test {
    _ = @import("import_tests.zig");
}
