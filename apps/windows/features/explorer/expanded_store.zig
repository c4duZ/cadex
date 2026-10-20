//! The open folders of each root, remembered across launches
//! (docs/spec/explorer.md): state, not settings, so not in settings.json;
//! %APPDATA%\Cadex\explorer.json, { "<root>": ["<open folder>", ...] }.

const std = @import("std");
const w = @import("win32");

const max_roots = 50;

fn path(gpa: std.mem.Allocator) ?[]u8 {
    return w.files.appData(gpa, "explorer.json") catch null;
}

/// The open folders saved for `root`, in `arena`; empty when none.
pub fn load(arena: std.mem.Allocator, root: []const u8) []const []const u8 {
    const file = path(arena) orelse return &.{};
    const data = w.files.read(arena, file, 1 << 20) orelse return &.{};
    const value = std.json.parseFromSliceLeaky(std.json.Value, arena, data, .{}) catch return &.{};
    if (value != .object) return &.{};
    const list = value.object.get(root) orelse return &.{};
    if (list != .array) return &.{};
    var out: std.ArrayList([]const u8) = .empty;
    for (list.array.items) |item| if (item == .string) out.append(arena, item.string) catch {};
    return out.items;
}

pub fn save(gpa: std.mem.Allocator, root: []const u8, open: []const []const u8) void {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const file = path(a) orelse return;
    var map: std.json.ObjectMap = .empty;
    if (w.files.read(a, file, 1 << 20)) |data| {
        if (std.json.parseFromSliceLeaky(std.json.Value, a, data, .{})) |v| {
            if (v == .object) map = v.object;
        } else |_| {}
    }
    var list: std.json.Array = .init(a);
    for (open) |p| list.append(.{ .string = p }) catch return;
    map.put(a, root, .{ .array = list }) catch return;
    // Old roots go first when there are too many.
    while (map.count() > max_roots) _ = map.orderedRemoveAt(0);
    var out: std.Io.Writer.Allocating = .init(a);
    std.json.Stringify.value(std.json.Value{ .object = map }, .{}, &out.writer) catch return;
    w.files.writeAtomic(gpa, file, out.written()) catch {};
}

test {
    @import("win32").refAllDeep(@This());
}
