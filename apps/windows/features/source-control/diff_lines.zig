//! Which lines a patch removed and added, read from its hunk headers (the
//! Mac's DiffLines.swift), and where each line of a text starts: the
//! side-by-side diff paints the marked lines and draws only those in view.

const std = @import("std");

/// The byte where each line starts; a text with n newlines has n + 1 lines.
pub fn lineStarts(gpa: std.mem.Allocator, text: []const u8) ![]u32 {
    var starts: std.ArrayList(u32) = .empty;
    errdefer starts.deinit(gpa);
    try starts.append(gpa, 0);
    for (text, 0..) |ch, i| {
        if (ch == '\n') try starts.append(gpa, @intCast(i + 1));
    }
    // A final newline does not open another line.
    if (text.len > 0 and text[text.len - 1] == '\n') _ = starts.pop();
    return starts.toOwnedSlice(gpa);
}

/// Line `i` (0-based) of `text`, without its line end.
pub fn line(text: []const u8, starts: []const u32, i: usize) []const u8 {
    const start = starts[i];
    var end: usize = if (i + 1 < starts.len) starts[i + 1] - 1 else text.len;
    if (end > start and text[end - 1] == '\r') end -= 1;
    return text[start..@max(end, start)];
}

pub const Marks = struct {
    /// removed[i]: line i (0-based) of the old text was removed.
    removed: []bool,
    added: []bool,

    pub fn deinit(self: *Marks, gpa: std.mem.Allocator) void {
        gpa.free(self.removed);
        gpa.free(self.added);
    }
};

/// The marks for texts of `old_lines` and `new_lines` lines.
pub fn marks(gpa: std.mem.Allocator, patch: []const u8, old_lines: usize, new_lines: usize) !Marks {
    const removed = try gpa.alloc(bool, old_lines);
    errdefer gpa.free(removed);
    const added = try gpa.alloc(bool, new_lines);
    @memset(removed, false);
    @memset(added, false);
    var old: usize = 0;
    var new: usize = 0;
    var in_hunk = false;
    var it = std.mem.splitScalar(u8, patch, '\n');
    while (it.next()) |l| {
        if (std.mem.startsWith(u8, l, "@@")) {
            const starts = hunkStarts(l);
            old = starts.old;
            new = starts.new;
            in_hunk = true;
            continue;
        }
        if (!in_hunk or l.len == 0) continue;
        switch (l[0]) {
            ' ' => {
                old += 1;
                new += 1;
            },
            '-' => {
                if (old >= 1 and old - 1 < removed.len) removed[old - 1] = true;
                old += 1;
            },
            '+' => {
                if (new >= 1 and new - 1 < added.len) added[new - 1] = true;
                new += 1;
            },
            else => {},
        }
    }
    return .{ .removed = removed, .added = added };
}

/// "@@ -12,3 +12,4 @@" -> 12 and 12 (1-based).
pub fn hunkStarts(header: []const u8) struct { old: usize, new: usize } {
    var old: usize = 1;
    var new: usize = 1;
    var parts = std.mem.tokenizeScalar(u8, header, ' ');
    while (parts.next()) |part| {
        if (part.len < 2) continue;
        const number = part[1 .. std.mem.indexOfScalar(u8, part, ',') orelse part.len];
        const value = std.fmt.parseInt(usize, number, 10) catch continue;
        if (part[0] == '-') old = value;
        if (part[0] == '+') new = value;
    }
    return .{ .old = old, .new = new };
}

const testing = std.testing;

test "hunk headers give where each side starts" {
    const s = hunkStarts("@@ -12,3 +14,4 @@ fn x()");
    try testing.expectEqual(@as(usize, 12), s.old);
    try testing.expectEqual(@as(usize, 14), s.new);
    try testing.expectEqual(@as(usize, 1), hunkStarts("@@ -0,0 +1 @@").new);
}

test "a patch marks the removed and added lines of each side" {
    const patch = "diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n";
    var m = try marks(testing.allocator, patch, 3, 3);
    defer m.deinit(testing.allocator);
    try testing.expectEqualSlices(bool, &.{ false, true, false }, m.removed);
    try testing.expectEqualSlices(bool, &.{ false, true, false }, m.added);
}

test "lines split on newlines, Windows line ends included" {
    const text = "a\r\nbb\nc\n";
    const starts = try lineStarts(testing.allocator, text);
    defer testing.allocator.free(starts);
    try testing.expectEqual(@as(usize, 3), starts.len);
    try testing.expectEqualStrings("a", line(text, starts, 0));
    try testing.expectEqualStrings("c", line(text, starts, 2));
}

test {
    @import("win32").refAllDeep(@This());
}
