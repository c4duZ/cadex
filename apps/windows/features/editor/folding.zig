//! Folded regions (docs/spec/editor.md, "Ver"): the core says which lines
//! start a block and where it ends; folding one keeps its first line and
//! hides the rest. Only the drawing skips them; the text is untouched.
//! Pure.

const std = @import("std");

/// 0-based lines; `end` is the last line inside the block.
pub const Region = struct { start: u32, end: u32 };

pub const Folding = struct {
    /// By start line, one per line (the outermost when several start there).
    regions: std.ArrayList(Region) = .empty,
    /// Start lines of the folded regions, sorted.
    folded: std.ArrayList(u32) = .empty,
    /// Bumped when what is hidden changes, for the rows to rebuild.
    version: u64 = 0,

    pub fn deinit(self: *Folding, gpa: std.mem.Allocator) void {
        self.regions.deinit(gpa);
        self.folded.deinit(gpa);
    }

    /// New regions from the core (after a load or an edit). Folds whose
    /// start line still starts a block stay folded.
    pub fn setRegions(self: *Folding, gpa: std.mem.Allocator, list: []const Region) !void {
        self.regions.clearRetainingCapacity();
        for (list) |r| {
            if (r.end <= r.start) continue;
            try self.regions.append(gpa, r);
        }
        std.mem.sort(Region, self.regions.items, {}, struct {
            fn less(_: void, a: Region, b: Region) bool {
                return a.start < b.start or (a.start == b.start and a.end > b.end);
            }
        }.less);
        // One per start line: the first, the widest, after the sort.
        var n: usize = 0;
        for (self.regions.items) |r| {
            if (n > 0 and self.regions.items[n - 1].start == r.start) continue;
            self.regions.items[n] = r;
            n += 1;
        }
        self.regions.shrinkRetainingCapacity(n);
        var kept: usize = 0;
        for (self.folded.items) |s| {
            if (self.regionAt(s) == null) continue;
            self.folded.items[kept] = s;
            kept += 1;
        }
        self.folded.shrinkRetainingCapacity(kept);
        self.version +%= 1;
    }

    /// The region that starts at `line`.
    pub fn regionAt(self: *const Folding, line: usize) ?Region {
        const items = self.regions.items;
        var lo: usize = 0;
        var hi: usize = items.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (items[mid].start < line) lo = mid + 1 else hi = mid;
        }
        if (lo < items.len and items[lo].start == line) return items[lo];
        return null;
    }

    pub fn isFolded(self: *const Folding, line: usize) bool {
        return std.sort.binarySearch(u32, self.folded.items, @as(u32, @intCast(line)), order) != null;
    }

    fn order(key: u32, item: u32) std.math.Order {
        return std.math.order(key, item);
    }

    pub fn toggle(self: *Folding, gpa: std.mem.Allocator, line: usize) !void {
        if (self.regionAt(line) == null) return;
        const l: u32 = @intCast(line);
        if (std.sort.binarySearch(u32, self.folded.items, l, order)) |i| {
            _ = self.folded.orderedRemove(i);
        } else {
            const at = std.sort.lowerBound(u32, self.folded.items, l, order);
            try self.folded.insert(gpa, at, l);
        }
        self.version +%= 1;
    }

    pub fn foldAll(self: *Folding, gpa: std.mem.Allocator) !void {
        self.folded.clearRetainingCapacity();
        for (self.regions.items) |r| try self.folded.append(gpa, r.start);
        self.version +%= 1;
    }

    pub fn unfoldAll(self: *Folding) void {
        if (self.folded.items.len == 0) return;
        self.folded.clearRetainingCapacity();
        self.version +%= 1;
    }

    /// The line drawn after `line`: past its block when it is folded.
    pub fn nextVisible(self: *const Folding, line: usize) usize {
        if (self.folded.items.len > 0 and self.isFolded(line)) {
            if (self.regionAt(line)) |r| return r.end + 1;
        }
        return line + 1;
    }

    /// The first line of the outermost folded block hiding `line`, or `line`.
    pub fn shownLine(self: *const Folding, line: usize) usize {
        var shown = line;
        for (self.folded.items) |s| {
            if (s >= line) break;
            const r = self.regionAt(s) orelse continue;
            if (line <= r.end) {
                shown = s;
                break;
            }
        }
        return shown;
    }
};

const testing = std.testing;

test "folding hides the block below its first line" {
    var f: Folding = .{};
    defer f.deinit(testing.allocator);
    try f.setRegions(testing.allocator, &.{ .{ .start = 4, .end = 6 }, .{ .start = 1, .end = 8 }, .{ .start = 1, .end = 3 } });
    try testing.expectEqual(@as(usize, 2), f.regions.items.len);
    try testing.expectEqual(@as(u32, 8), f.regionAt(1).?.end);
    try testing.expect(f.regionAt(2) == null);
    try f.toggle(testing.allocator, 4);
    try testing.expectEqual(@as(usize, 7), f.nextVisible(4));
    try testing.expectEqual(@as(usize, 4), f.shownLine(5));
    try f.toggle(testing.allocator, 1);
    try testing.expectEqual(@as(usize, 1), f.shownLine(5));
    try f.toggle(testing.allocator, 1);
    try testing.expect(!f.isFolded(1));
    try f.foldAll(testing.allocator);
    try testing.expect(f.isFolded(1) and f.isFolded(4));
    try f.setRegions(testing.allocator, &.{.{ .start = 4, .end = 5 }});
    try testing.expect(f.isFolded(4) and !f.isFolded(1));
    f.unfoldAll();
    try testing.expectEqual(@as(usize, 5), f.nextVisible(4));
}

test {
    @import("win32").refAllDeep(@This());
}
