//! The 46 themes that ship with the app: the Mac's
//! apps/macos/features/themes/Resources/catalog.json, embedded by the build,
//! so both apps read the same file (built by tools/themes/build_catalog.py).

const std = @import("std");
const theme = @import("theme.zig");

pub const default_id = "caffeine";

const bytes = @embedFile("theme_catalog");

/// Every built-in family, in the file's order; parsed once, kept for the
/// life of the app. Empty only if the file is broken, which the tests catch.
pub fn families(gpa: std.mem.Allocator) []const theme.Family {
    const State = struct {
        var loaded: ?[]const theme.Family = null;
    };
    if (State.loaded) |list| return list;
    const list = parse(gpa, bytes) catch &.{};
    State.loaded = list;
    return list;
}

fn parse(gpa: std.mem.Allocator, data: []const u8) ![]const theme.Family {
    // Kept for the app's life: the families point into this tree.
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, data, .{});
    const root = parsed.value;
    if (root != .object) return error.InvalidTheme;
    const list = root.object.get("families") orelse return error.InvalidTheme;
    if (list != .array) return error.InvalidTheme;
    var out: std.ArrayList(theme.Family) = .empty;
    for (list.array.items) |entry| {
        if (entry != .object) continue;
        const o = entry.object;
        const id = o.get("id") orelse continue;
        const name = o.get("name") orelse continue;
        if (id != .string or name != .string) continue;
        const description = if (o.get("description")) |d| (if (d == .string) d.string else "") else "";
        const dark = if (o.get("dark")) |v| (if (v == .object) theme.variant(v.object, name.string, true) catch null else null) else null;
        const light = if (o.get("light")) |v| (if (v == .object) theme.variant(v.object, name.string, false) catch null else null) else null;
        if (dark == null and light == null) continue;
        try out.append(gpa, .{ .id = id.string, .name = name.string, .description = description, .dark = dark, .light = light });
    }
    return out.toOwnedSlice(gpa);
}

pub fn find(gpa: std.mem.Allocator, id: []const u8) ?theme.Family {
    for (families(gpa)) |f| if (std.mem.eql(u8, f.id, id)) return f;
    return null;
}

test "the catalog has the 46 themes, Caffeine among them, both versions" {
    const list = families(std.heap.page_allocator);
    try std.testing.expectEqual(@as(usize, 46), list.len);
    const caffeine = find(std.heap.page_allocator, default_id).?;
    try std.testing.expect(caffeine.dark != null and caffeine.light != null);
}
