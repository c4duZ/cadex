//! A theme (docs/spec/themes.md): the interface colors and the terminal's,
//! as in apps/macos/features/themes/Theme.swift, read from the same JSON.

const std = @import("std");

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
    id: []const u8,
    name: []const u8,
    description: []const u8,
    dark: ?Theme,
    light: ?Theme,

    /// The version asked for, or the one the family has.
    pub fn theme(self: Family, dark: bool) Theme {
        if (dark) return self.dark orelse self.light.?;
        return self.light orelse self.dark.?;
    }
};

pub const Error = error{InvalidTheme};

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

fn color(object: std.json.ObjectMap, key: []const u8) Error!u32 {
    const value = object.get(key) orelse return error.InvalidTheme;
    if (value != .string) return error.InvalidTheme;
    return parseColor(value.string);
}

fn section(object: std.json.ObjectMap, key: []const u8) Error!std.json.ObjectMap {
    const value = object.get(key) orelse return error.InvalidTheme;
    if (value != .object) return error.InvalidTheme;
    return value.object;
}

/// One version of a family ({ "interface": {...}, "terminal": {...} }).
pub fn variant(object: std.json.ObjectMap, name: []const u8, dark: bool) Error!Theme {
    const ui = try section(object, "interface");
    const term = try section(object, "terminal");
    const ansi_value = term.get("ansi") orelse return error.InvalidTheme;
    if (ansi_value != .array or ansi_value.array.items.len != 16) return error.InvalidTheme;
    var ansi: [16]u32 = undefined;
    for (ansi_value.array.items, 0..) |v, i| {
        if (v != .string) return error.InvalidTheme;
        ansi[i] = try parseColor(v.string);
    }
    return .{
        .name = name,
        .dark = dark,
        .interface = .{
            .chrome = try color(ui, "chrome"),
            .panel = try color(ui, "panel"),
            .panel_border = try color(ui, "panelBorder"),
            .tab_active = try color(ui, "tabActive"),
            .field = try color(ui, "field"),
            .text = try color(ui, "text"),
            .secondary_text = try color(ui, "secondaryText"),
            .accent = try color(ui, "accent"),
        },
        .terminal = .{
            .background = try color(term, "background"),
            .foreground = try color(term, "foreground"),
            .cursor = try color(term, "cursor"),
            .selection = try color(term, "selection"),
            .ansi = ansi,
        },
    };
}

const testing = std.testing;

test "colors in the three accepted forms, others refused" {
    try testing.expectEqual(@as(u32, 0xaabbcc), try parseColor("#abc"));
    try testing.expectEqual(@as(u32, 0x112233), try parseColor("#112233"));
    try testing.expectEqual(@as(u32, 0x112233), try parseColor("#11223344"));
    try testing.expectError(error.InvalidTheme, parseColor("112233"));
    try testing.expectError(error.InvalidTheme, parseColor("#12345"));
}
