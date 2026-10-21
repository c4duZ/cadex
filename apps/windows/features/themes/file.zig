//! The Cadex theme file (docs/spec/themes.md), as the Mac's ThemeFile.swift:
//! JSON with the interface and terminal colors as "#RRGGBB". Reading it
//! names the field that is wrong; writing gives the Mac's sorted keys.
//!
//!     { "name": "My theme", "dark": true,
//!       "interface": { "chrome": "#252525", "panel": "#161616", ... },
//!       "terminal": { "background": "#161616", ..., "ansi": [16 colors] } }

const std = @import("std");
const t = @import("strings").t;
const theme = @import("theme.zig");

const Theme = theme.Theme;

/// A theme from a file's bytes; its name is copied into `arena`. `dark`
/// is true when the file leaves it out, as on the Mac.
pub fn read(arena: std.mem.Allocator, gpa: std.mem.Allocator, data: []const u8, problem: *theme.Problem) theme.Error!Theme {
    const parsed = std.json.parseFromSlice(std.json.Value, gpa, data, .{}) catch return fail(problem, "(file)", t("not a JSON object", "não é um objeto JSON"));
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return fail(problem, "(file)", t("not a JSON object", "não é um objeto JSON"));
    const name_value = root.object.get("name");
    if (name_value == null or name_value.? != .string or name_value.?.string.len == 0) {
        return fail(problem, "name", t("the theme's name is missing", "falta o nome do tema"));
    }
    const dark = if (root.object.get("dark")) |d| (if (d == .bool) d.bool else true) else true;
    const name = arena.dupe(u8, name_value.?.string) catch return error.InvalidTheme;
    return theme.variant(root.object, name, dark, problem);
}

fn fail(problem: *theme.Problem, field: []const u8, message: []const u8) theme.Error {
    problem.* = .{ .field = field, .message = message };
    return error.InvalidTheme;
}

/// The file form of a theme, the inverse of `read`; owned by the caller.
pub fn write(gpa: std.mem.Allocator, th: Theme) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const ui = th.interface;
    const term = th.terminal;
    try out.print(gpa, "{{\n  \"dark\" : {},\n  \"interface\" : {{\n", .{th.dark});
    const ui_fields = [_]struct { []const u8, u32 }{
        .{ "accent", ui.accent },       .{ "chrome", ui.chrome },               .{ "field", ui.field },
        .{ "panel", ui.panel },         .{ "panelBorder", ui.panel_border },    .{ "secondaryText", ui.secondary_text },
        .{ "tabActive", ui.tab_active }, .{ "text", ui.text },
    };
    for (ui_fields, 0..) |f, i| try out.print(gpa, "    \"{s}\" : \"#{X:0>6}\"{s}\n", .{ f[0], f[1], comma(i, ui_fields.len) });
    try out.appendSlice(gpa, "  },\n  \"name\" : ");
    try appendString(gpa, &out, th.name);
    try out.appendSlice(gpa, ",\n  \"terminal\" : {\n    \"ansi\" : [\n");
    for (term.ansi, 0..) |a, i| try out.print(gpa, "      \"#{X:0>6}\"{s}\n", .{ a, comma(i, 16) });
    try out.print(gpa, "    ],\n    \"background\" : \"#{X:0>6}\",\n    \"cursor\" : \"#{X:0>6}\",\n", .{ term.background, term.cursor });
    try out.print(gpa, "    \"foreground\" : \"#{X:0>6}\",\n    \"selection\" : \"#{X:0>6}\"\n  }}\n}}\n", .{ term.foreground, term.selection });
    return out.toOwnedSlice(gpa);
}

fn comma(i: usize, count: usize) []const u8 {
    return if (i + 1 < count) "," else "";
}

/// A JSON string: quotes, backslashes and control characters escaped.
fn appendString(gpa: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8) !void {
    try out.append(gpa, '"');
    for (text) |ch| switch (ch) {
        '"' => try out.appendSlice(gpa, "\\\""),
        '\\' => try out.appendSlice(gpa, "\\\\"),
        '\n' => try out.appendSlice(gpa, "\\n"),
        0...9, 11...0x1f => try out.print(gpa, "\\u{x:0>4}", .{ch}),
        else => try out.append(gpa, ch),
    };
    try out.append(gpa, '"');
}

const testing = std.testing;

pub const sample: Theme = .{
    .name = "Meu \"tema\"",
    .dark = false,
    .interface = .{ .chrome = 0xeeeeee, .panel = 0xffffff, .panel_border = 0xdddddd, .tab_active = 0xe0e0ff, .field = 0xf4f4f4, .text = 0x111111, .secondary_text = 0x666666, .accent = 0x3366ff },
    .terminal = .{ .background = 0xffffff, .foreground = 0x111111, .cursor = 0x3366ff, .selection = 0xccccff, .ansi = .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 0xffffff } },
};

test "a theme written and read back is the same" {
    const text = try write(testing.allocator, sample);
    defer testing.allocator.free(text);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var problem: theme.Problem = .{};
    const back = try read(arena.allocator(), testing.allocator, text, &problem);
    try testing.expectEqualStrings(sample.name, back.name);
    try testing.expectEqual(sample.dark, back.dark);
    try testing.expectEqual(sample.interface, back.interface);
    try testing.expectEqual(sample.terminal, back.terminal);
}

test "a broken file names the field" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var problem: theme.Problem = .{};
    try testing.expectError(error.InvalidTheme, read(arena.allocator(), testing.allocator, "{\"name\":\"x\",\"interface\":{},\"terminal\":{}}", &problem));
    try testing.expectEqualStrings("chrome", problem.field);
    try testing.expectError(error.InvalidTheme, read(arena.allocator(), testing.allocator, "[1]", &problem));
    try testing.expectEqualStrings("(file)", problem.field);
}
