//! What the view draws, top to bottom: each line not hidden by a fold, in
//! as many rows as it wraps into (wrap.zig). Rebuilt when the text, the
//! folds or the width change; the view keeps only the rows on screen in
//! the painter's hands, so a file of 10 MB scrolls like a small one. Pure.

const std = @import("std");
const Buffer = @import("buffer.zig").Buffer;
const Folding = @import("folding.zig").Folding;
const wrap = @import("wrap.zig");

pub const Row = struct {
    line: u32,
    start: u32,
    end: u32,
    /// The first row of its line (the one with the number and the arrow).
    first: bool,
    /// The last row of its line: the caret can stand at its end.
    last: bool,
};

pub const Rows = struct {
    items: std.ArrayList(Row) = .empty,
    /// What the rows were built from, to know when to build again.
    built: struct { text: u64 = std.math.maxInt(u64), folds: u64 = 0, cols: usize = 0 } = .{},

    pub fn deinit(self: *Rows, gpa: std.mem.Allocator) void {
        self.items.deinit(gpa);
    }

    /// Builds again if the text, the folds or the width changed.
    pub fn update(self: *Rows, gpa: std.mem.Allocator, buffer: *const Buffer, folding: *const Folding, cols: usize) !void {
        if (self.built.text == buffer.version and self.built.folds == folding.version and self.built.cols == cols) return;
        self.items.clearRetainingCapacity();
        var segments: std.ArrayList(wrap.Segment) = .empty;
        defer segments.deinit(gpa);
        var line: usize = 0;
        while (line < buffer.lineCount()) : (line = folding.nextVisible(line)) {
            segments.clearRetainingCapacity();
            try wrap.splitLine(gpa, buffer.text(), buffer.lineStart(line), buffer.lineEnd(line), cols, &segments);
            for (segments.items, 0..) |s, i| try self.items.append(gpa, .{
                .line = @intCast(line),
                .start = s.start,
                .end = s.end,
                .first = i == 0,
                .last = i + 1 == segments.items.len,
            });
        }
        self.built = .{ .text = buffer.version, .folds = folding.version, .cols = cols };
    }

    pub fn count(self: *const Rows) usize {
        return self.items.items.len;
    }

    /// The row the caret at byte `at` stands on. At the break between two
    /// rows of a line, the second (where typing goes on).
    pub fn rowOf(self: *const Rows, at: usize) usize {
        const items = self.items.items;
        if (items.len == 0) return 0;
        var lo: usize = 0;
        var hi: usize = items.len;
        while (hi - lo > 1) {
            const mid = (lo + hi) / 2;
            if (items[mid].start <= at) lo = mid else hi = mid;
        }
        return lo;
    }

    /// The first row of `line`, or of the fold that hides it.
    pub fn rowOfLine(self: *const Rows, line: usize) usize {
        const items = self.items.items;
        var lo: usize = 0;
        var hi: usize = items.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            if (items[mid].line < line) lo = mid + 1 else hi = mid;
        }
        if (lo < items.len and items[lo].line == line) return lo;
        return lo -| 1;
    }
};

const testing = std.testing;

test "rows wrap long lines and skip folded ones" {
    const gpa = testing.allocator;
    var b = try Buffer.init(gpa, "fn a() {\n    x;\n}\nlonger line here\n");
    defer b.deinit();
    var f: Folding = .{};
    defer f.deinit(gpa);
    try f.setRegions(gpa, &.{.{ .start = 0, .end = 2 }});
    var rows: Rows = .{};
    defer rows.deinit(gpa);
    try rows.update(gpa, &b, &f, 10);
    // 3 short lines, the long one in 2, the empty last line.
    try testing.expectEqual(@as(usize, 6), rows.count());
    try testing.expect(rows.items.items[3].first and !rows.items.items[3].last);
    try testing.expectEqual(@as(usize, 4), rows.rowOf(b.lineStart(3) + 12));
    try f.toggle(gpa, 0);
    try rows.update(gpa, &b, &f, 10);
    try testing.expectEqual(@as(usize, 4), rows.count());
    try testing.expectEqual(@as(u32, 3), rows.items.items[1].line);
    try testing.expectEqual(@as(usize, 0), rows.rowOfLine(1));
    try testing.expectEqual(@as(usize, 1), rows.rowOfLine(3));
}

test {
    @import("win32").refAllDeep(@This());
}
