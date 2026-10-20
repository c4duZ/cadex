//! The selected files of the Git lists, by path and list, so a refresh
//! (which rebuilds every row) keeps them. The commands git.stage,
//! git.discard and the others act on these.

const std = @import("std");
const status_mod = @import("status.zig");

const Entry = status_mod.Entry;

pub const Selected = struct { entry: Entry, staged: bool };

pub const Selection = struct {
    keys: std.ArrayList(Key) = .empty,

    const Key = struct { staged: bool, path: []u8 };

    pub fn deinit(self: *Selection, gpa: std.mem.Allocator) void {
        self.clear(gpa);
        self.keys.deinit(gpa);
    }

    pub fn clear(self: *Selection, gpa: std.mem.Allocator) void {
        for (self.keys.items) |k| gpa.free(k.path);
        self.keys.clearRetainingCapacity();
    }

    pub fn isEmpty(self: *const Selection) bool {
        return self.keys.items.len == 0;
    }

    fn find(self: *const Selection, staged: bool, path: []const u8) ?usize {
        for (self.keys.items, 0..) |k, i| {
            if (k.staged == staged and std.mem.eql(u8, k.path, path)) return i;
        }
        return null;
    }

    pub fn has(self: *const Selection, staged: bool, path: []const u8) bool {
        return self.find(staged, path) != null;
    }

    /// A plain click: only this file.
    pub fn only(self: *Selection, gpa: std.mem.Allocator, staged: bool, path: []const u8) void {
        self.clear(gpa);
        self.add(gpa, staged, path);
    }

    /// Ctrl+click: in or out of the selection.
    pub fn toggle(self: *Selection, gpa: std.mem.Allocator, staged: bool, path: []const u8) void {
        if (self.find(staged, path)) |i| {
            gpa.free(self.keys.orderedRemove(i).path);
            return;
        }
        self.add(gpa, staged, path);
    }

    fn add(self: *Selection, gpa: std.mem.Allocator, staged: bool, path: []const u8) void {
        const copy = gpa.dupe(u8, path) catch return;
        self.keys.append(gpa, .{ .staged = staged, .path = copy }) catch gpa.free(copy);
    }

    /// The selected files still in `status`, in selection order.
    pub fn entries(self: *const Selection, gpa: std.mem.Allocator, status: ?status_mod.Status) []Selected {
        const s = status orelse return &.{};
        var out: std.ArrayList(Selected) = .empty;
        for (self.keys.items) |k| {
            for (s.entries) |e| {
                if (!std.mem.eql(u8, e.path, k.path)) continue;
                const in = if (k.staged) e.isStaged() else (e.isUnstaged() or e.kind == .conflict);
                if (in) out.append(gpa, .{ .entry = e, .staged = k.staged }) catch {};
                break;
            }
        }
        return out.toOwnedSlice(gpa) catch &.{};
    }
};

test "the selection follows paths across a refresh" {
    const gpa = std.testing.allocator;
    var sel: Selection = .{};
    defer sel.deinit(gpa);
    sel.only(gpa, false, "a.zig");
    sel.toggle(gpa, true, "b.zig");
    try std.testing.expect(sel.has(true, "b.zig"));
    sel.toggle(gpa, true, "b.zig");
    try std.testing.expect(!sel.has(true, "b.zig"));
    var s = try status_mod.parse(gpa, try gpa.dupe(u8, "main\tabc\t\t0\t0\n0\t.\tM\ta.zig\t\n"));
    defer s.deinit(gpa);
    const picked = sel.entries(gpa, s);
    defer gpa.free(picked);
    try std.testing.expectEqual(@as(usize, 1), picked.len);
    try std.testing.expectEqualStrings("a.zig", picked[0].entry.path);
}

test {
    @import("win32").refAllDeep(@This());
}
