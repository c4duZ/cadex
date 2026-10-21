//! A theme (docs/spec/themes.md): the interface colors and the terminal's,
//! as in apps/macos/features/themes/Theme.swift, read from the same JSON.

const std = @import("std");
const t = @import("strings").t;

pub const Interface = struct {
    chrome: u32,
    panel: u32,
    panel_border: u32,
    tab_active: u32,
    field: u32,
    text: u32,
    secondary_text: u32,
    accent: u32,
};

pub const Terminal = struct {
    background: u32,
    foreground: u32,
    cursor: u32,
    selection: u32,
    /// black, red, green, yellow, blue, magenta, cyan, white, then bright.
    ansi: [16]u32,
};

pub const Theme = struct {
    name: []const u8,
    dark: bool,
    interface: Interface,
    terminal: Terminal,
};

pub const Family = struct {
    /// Stable, lowercase ("caffeine"); "user:<file>" for the user's own.
    id: []const u8,
    name: []const u8,
    /// One line in the interface's language.
    description: []const u8,
    /// Where the colors come from: "official", "tweakcn", "base16",
    /// "base24" or "user" (a file in the user's themes folder).
    source: []const u8 = "official",
    dark: ?Theme,
    light: ?Theme,

    /// The version asked for, or the one the family has.
    pub fn theme(self: Family, dark: bool) Theme {
        if (dark) return self.dark orelse self.light.?;
        return self.light orelse self.dark.?;
    }
};

pub const Error = error{InvalidTheme};

/// Which field of a theme file was wrong, and why: the themes page lists
/// it next to the file's name, as the Mac's ThemeFile.Problem does.
pub const Problem = struct {
    field: []const u8 = "",
    message: []const u8 = "",
};

/// "#RGB", "#RRGGBB" or "#RRGGBBAA" (the alpha is ignored), as the Mac reads it.
pub fn parseColor(text: []const u8) Error!u32 {
    if (text.len < 4 or text[0] != '#') return error.InvalidTheme;
    const hex = text[1..];
    var six: [6]u8 = undefined;
    const digits: []const u8 = switch (hex.len) {
        3 => blk: {
            for (hex, 0..) |ch, i| {
                six[2 * i] = ch;
                six[2 * i + 1] = ch;
            }
            break :blk &six;
        },
        6 => hex,
        8 => hex[0..6],
        else => return error.InvalidTheme,
    };
    return std.fmt.parseInt(u32, digits, 16) catch error.InvalidTheme;
}

fn color(object: std.json.ObjectMap, key: []const u8, problem: ?*Problem) Error!u32 {
    errdefer if (problem) |p| {
        p.* = .{ .field = key, .message = t("missing, or not a #RRGGBB color", "falta, ou não é uma cor #RRGGBB") };
    };
    const value = object.get(key) orelse return error.InvalidTheme;
    if (value != .string) return error.InvalidTheme;
    return parseColor(value.string);
}

fn section(object: std.json.ObjectMap, key: []const u8, problem: ?*Problem) Error!std.json.ObjectMap {
    errdefer if (problem) |p| {
        p.* = .{ .field = key, .message = t("missing section", "falta a seção") };
    };
    const value = object.get(key) orelse return error.InvalidTheme;
    if (value != .object) return error.InvalidTheme;
    return value.object;
}

/// One version of a family ({ "interface": {...}, "terminal": {...} }).
/// `problem`, when given, names the field that was wrong.
pub fn variant(object: std.json.ObjectMap, name: []const u8, dark: bool, problem: ?*Problem) Error!Theme {
    const ui = try section(object, "interface", problem);
    const term = try section(object, "terminal", problem);
    return .{
        .name = name,
        .dark = dark,
        .interface = .{
            .chrome = try color(ui, "chrome", problem),
            .panel = try color(ui, "panel", problem),
            .panel_border = try color(ui, "panelBorder", problem),
            .tab_active = try color(ui, "tabActive", problem),
            .field = try color(ui, "field", problem),
            .text = try color(ui, "text", problem),
            .secondary_text = try color(ui, "secondaryText", problem),
            .accent = try color(ui, "accent", problem),
        },
        .terminal = .{
            .background = try color(term, "background", problem),
            .foreground = try color(term, "foreground", problem),
            .cursor = try color(term, "cursor", problem),
            .selection = try color(term, "selection", problem),
            .ansi = try ansiColors(term, problem),
        },
    };
}

fn ansiColors(term: std.json.ObjectMap, problem: ?*Problem) Error![16]u32 {
    errdefer if (problem) |p| {
        p.* = .{ .field = "terminal.ansi", .message = t("needs 16 #RRGGBB colors", "precisa de 16 cores #RRGGBB") };
    };
    const value = term.get("ansi") orelse return error.InvalidTheme;
    if (value != .array or value.array.items.len != 16) return error.InvalidTheme;
    var ansi: [16]u32 = undefined;
    for (value.array.items, 0..) |v, i| {
        if (v != .string) return error.InvalidTheme;
        ansi[i] = try parseColor(v.string);
    }
    return ansi;
}

/// This color moved a fraction `t` toward `other` (the Mac's RGB.mixed).
pub fn mix(a: u32, b: u32, amount: f64) u32 {
    var out: u32 = 0;
    inline for (.{ 16, 8, 0 }) |shift| {
        const x: f64 = @floatFromInt((a >> shift) & 0xff);
        const y: f64 = @floatFromInt((b >> shift) & 0xff);
        out |= @as(u32, @intFromFloat(@round(x + (y - x) * amount))) << shift;
    }
    return out;
}

/// WCAG relative luminance, 0 (black) to 1 (white).
pub fn luminance(rgb: u32) f64 {
    var sum: f64 = 0;
    inline for (.{ .{ 16, 0.2126 }, .{ 8, 0.7152 }, .{ 0, 0.0722 } }) |part| {
        const ch: f64 = @as(f64, @floatFromInt((rgb >> part[0]) & 0xff)) / 255;
        sum += part[1] * (if (ch <= 0.04045) ch / 12.92 else std.math.pow(f64, (ch + 0.055) / 1.055, 2.4));
    }
    return sum;
}

const testing = std.testing;

test "colors in the three accepted forms, others refused" {
    try testing.expectEqual(@as(u32, 0xaabbcc), try parseColor("#abc"));
    try testing.expectEqual(@as(u32, 0x112233), try parseColor("#112233"));
    try testing.expectEqual(@as(u32, 0x112233), try parseColor("#11223344"));
    try testing.expectError(error.InvalidTheme, parseColor("112233"));
    try testing.expectError(error.InvalidTheme, parseColor("#12345"));
}

test "mixing and luminance as the Mac computes them" {
    try testing.expectEqual(@as(u32, 0x808080), mix(0x000000, 0xffffff, 0.5));
    try testing.expectEqual(@as(u32, 0x112233), mix(0x112233, 0xffffff, 0));
    try testing.expect(luminance(0x000000) == 0);
    try testing.expect(@abs(luminance(0xffffff) - 1) < 1e-9);
}
