//! The themes that ship with the app: the Mac's
//! apps/macos/features/themes/Resources/catalog.json, embedded by the build,
//! so both apps read the same file (built by tools/themes/build_catalog.py
//! from the official palettes, the tweakcn presets and base16/base24).
//! Read when asked and not kept, as the Mac's ThemeCatalog: the parse tree
//! is freed before returning and only the families asked for are copied
//! (plan 15: hundreds of themes must not weigh on the app).

const std = @import("std");
const strings = @import("strings");
const theme = @import("theme.zig");

const Family = theme.Family;

/// The family the app starts with: the one the owner uses.
pub const default_id = "caffeine";

const bytes = @embedFile("theme_catalog");

/// Appends every built-in family, in the file's order (the default first),
/// with its strings in `arena`; `gpa` holds the parse tree meanwhile.
pub fn appendAll(gpa: std.mem.Allocator, arena: std.mem.Allocator, out: *std.ArrayList(Family)) !void {
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, bytes, .{});
    defer parsed.deinit();
    for (try entries(parsed.value)) |entry| {
        const f = family(arena, entry) catch continue;
        try out.append(arena, f);
    }
}

/// One built-in family, its strings in `arena`; null when there is none.
pub fn find(gpa: std.mem.Allocator, arena: std.mem.Allocator, id: []const u8) ?Family {
    const parsed = std.json.parseFromSlice(std.json.Value, gpa, bytes, .{}) catch return null;
    defer parsed.deinit();
    for (entries(parsed.value) catch return null) |entry| {
        const entry_id = if (entry == .object) entry.object.get("id") else null;
        if (entry_id == null or entry_id.? != .string or !std.mem.eql(u8, entry_id.?.string, id)) continue;
        return family(arena, entry) catch null;
    }
    return null;
}

fn entries(root: std.json.Value) theme.Error![]const std.json.Value {
    if (root != .object) return error.InvalidTheme;
    const list = root.object.get("families") orelse return error.InvalidTheme;
    if (list != .array) return error.InvalidTheme;
    return list.array.items;
}

/// A family of the file, copied out of the parse tree into `arena`.
fn family(arena: std.mem.Allocator, entry: std.json.Value) !Family {
    if (entry != .object) return error.InvalidTheme;
    const o = entry.object;
    const id = try string(o, "id");
    const name = try arena.dupe(u8, try string(o, "name"));
    const dark = try version(o, "dark", name, true);
    const light = try version(o, "light", name, false);
    if (dark == null and light == null) return error.InvalidTheme;
    return .{
        .id = try arena.dupe(u8, id),
        .name = name,
        .description = try arena.dupe(u8, description(o)),
        .source = try arena.dupe(u8, string(o, "source") catch "official"),
        .dark = dark,
        .light = light,
    };
}

fn string(o: std.json.ObjectMap, key: []const u8) theme.Error![]const u8 {
    const value = o.get(key) orelse return error.InvalidTheme;
    return if (value == .string) value.string else error.InvalidTheme;
}

fn version(o: std.json.ObjectMap, key: []const u8, name: []const u8, dark: bool) theme.Error!?theme.Theme {
    const value = o.get(key) orelse return null;
    if (value != .object) return error.InvalidTheme;
    return try theme.variant(value.object, name, dark, null);
}

/// The description in the interface's language: a pair {"en", "pt"} since
/// plan 15, a plain string before. Not through strings.t: its table of
/// pairs is for the app's few hundred fixed texts, not every theme's.
fn description(o: std.json.ObjectMap) []const u8 {
    const value = o.get("description") orelse return "";
    switch (value) {
        .string => |s| return s,
        .object => |pair| {
            const key = if (strings.language == .pt) "pt" else "en";
            const text = pair.get(key) orelse pair.get("en") orelse return "";
            return if (text == .string) text.string else "";
        },
        else => return "",
    }
}

const testing = std.testing;

test "the catalog has hundreds of themes, Caffeine first, both versions" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var list: std.ArrayList(Family) = .empty;
    try appendAll(testing.allocator, arena.allocator(), &list);
    try testing.expect(list.items.len > 300);
    try testing.expectEqualStrings(default_id, list.items[0].id);
    try testing.expect(list.items[0].dark != null and list.items[0].light != null);
}

test "find copies one family by id, its description in the interface's language" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    strings.language = .pt;
    defer strings.language = .en;
    const caffeine = find(testing.allocator, arena.allocator(), default_id).?;
    try testing.expectEqualStrings("Caffeine", caffeine.name);
    try testing.expectEqualStrings("Tons de café: creme e espresso.", caffeine.description);
    try testing.expectEqualStrings("tweakcn", caffeine.source);
    try testing.expect(find(testing.allocator, arena.allocator(), "no-such-theme") == null);
}
