//! The daemon's copy of a session's raw output (docs/adr/0022-terminal-daemon.md):
//! the last `limit` bytes the program wrote, replayed into the app's model
//! when it attaches again. Grows as output comes, so an idle shell costs
//! little; when full, the oldest part goes, cut after a line end so the
//! replay starts at the start of a line.

const std = @import("std");

/// 2 MiB: more than the 10 thousand lines of history the app keeps for
/// plain output; a TUI's redraws push old output out sooner, and the
/// resize on attach makes the TUI draw itself again anyway.
pub const default_limit = 2 * 1024 * 1024;

/// How far past the cut a line end is looked for before cutting mid-line.
const line_search = 4096;

pub const Ring = struct {
    bytes: std.ArrayList(u8) = .empty,
    limit: usize = default_limit,

    pub fn deinit(self: *Ring, gpa: std.mem.Allocator) void {
        self.bytes.deinit(gpa);
    }

    /// Keeps `data` and drops from the front what goes over the limit.
    pub fn append(self: *Ring, gpa: std.mem.Allocator, data: []const u8) !void {
        if (data.len >= self.limit) {
            self.bytes.clearRetainingCapacity();
            try self.bytes.appendSlice(gpa, data[data.len - self.limit ..]);
            self.trimToLine(0);
            return;
        }
        const over = (self.bytes.items.len + data.len) -| self.limit;
        if (over > 0) self.trimToLine(over);
        try self.bytes.appendSlice(gpa, data);
    }

    /// Drops at least `count` bytes, up to the next line end if one is near.
    fn trimToLine(self: *Ring, count: usize) void {
        const items = self.bytes.items;
        var cut = @min(count, items.len);
        const end = @min(items.len, cut + line_search);
        if (std.mem.indexOfScalarPos(u8, items[0..end], cut, '\n')) |nl| cut = nl + 1;
        if (cut == 0) return;
        std.mem.copyForwards(u8, items[0 .. items.len - cut], items[cut..]);
        self.bytes.shrinkRetainingCapacity(items.len - cut);
    }

    pub fn contents(self: *const Ring) []const u8 {
        return self.bytes.items;
    }
};

const testing = std.testing;

test "the ring keeps the newest output and starts at a line" {
    var ring: Ring = .{ .limit = 16 };
    defer ring.deinit(testing.allocator);
    try ring.append(testing.allocator, "one\ntwo\n");
    try testing.expectEqualStrings("one\ntwo\n", ring.contents());
    try ring.append(testing.allocator, "three\nfour\n");
    // 19 bytes: over by 3, cut after the next line end ("one\n").
    try testing.expectEqualStrings("two\nthree\nfour\n", ring.contents());
    try ring.append(testing.allocator, "a much longer line than the limit\nend\n");
    try testing.expectEqualStrings("end\n", ring.contents());
}
