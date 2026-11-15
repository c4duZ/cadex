//! A merge conflict resolved block by block (docs/spec/source-control.md,
//! Conflito em três vias; plan 21 phase C). The blocks are the markers git
//! leaves in the file: `<<<<<<<` ours, `|||||||` the base (diff3, when on),
//! `=======` theirs, `>>>>>>>`. A block is replaced by ours, theirs or both;
//! "Mark resolved" refuses while a marker is left, then saves the file
//! atomically and stages it.

const std = @import("std");
const fs = @import("../../shared/fs.zig");
const workspace = @import("../workspace/workspace.zig");
const git = @import("git.zig");
const language = @import("../../shared/language.zig");

/// Line indices (0-based) of one block: the marker lines and the ranges
/// between them (end exclusive). `base_start` is null without a base part.
pub const Block = struct {
    start: usize,
    ours: [2]usize,
    base: ?[2]usize,
    theirs: [2]usize,
    end: usize,
};

pub const Choice = enum(u8) { ours = 0, theirs = 1, both = 2 };

fn marker(line: []const u8, comptime sign: u8) bool {
    if (line.len < 7) return false;
    for (line[0..7]) |c| if (c != sign) return false;
    // "=======" stands alone; the others may carry a label.
    return if (sign == '=') std.mem.trim(u8, line[7..], " \r").len == 0 else line.len == 7 or line[7] == ' ' or line[7] == '\r';
}

/// The blocks of `text`, in order; a block left open at the end is not one.
pub fn blocks(gpa: std.mem.Allocator, text: []const u8) ![]Block {
    var out: std.ArrayList(Block) = .empty;
    errdefer out.deinit(gpa);
    var lines = std.mem.splitScalar(u8, text, '\n');
    var index: usize = 0;
    var open: ?Block = null;
    var part: enum { ours, base, theirs } = .ours;
    while (lines.next()) |line| : (index += 1) {
        if (marker(line, '<')) {
            open = .{ .start = index, .ours = .{ index + 1, index + 1 }, .base = null, .theirs = .{ 0, 0 }, .end = 0 };
            part = .ours;
            continue;
        }
        var b = &(open orelse continue);
        if (part == .ours and marker(line, '|')) {
            b.ours[1] = index;
            b.base = .{ index + 1, index + 1 };
            part = .base;
        } else if (part != .theirs and marker(line, '=')) {
            if (part == .ours) b.ours[1] = index else b.base.?[1] = index;
            b.theirs = .{ index + 1, index + 1 };
            part = .theirs;
        } else if (part == .theirs and marker(line, '>')) {
            b.theirs[1] = index;
            b.end = index;
            try out.append(gpa, b.*);
            open = null;
        }
    }
    return out.toOwnedSlice(gpa);
}

/// `text` with block `which` replaced by its ours, theirs or both (ours
/// then theirs). Caller frees.
pub fn resolve(gpa: std.mem.Allocator, text: []const u8, which: usize, choice: Choice) ![]u8 {
    const all = try blocks(gpa, text);
    defer gpa.free(all);
    if (which >= all.len) return error.NotFound;
    const b = all[which];
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var lines = std.mem.splitScalar(u8, text, '\n');
    var index: usize = 0;
    var first = true;
    while (lines.next()) |line| : (index += 1) {
        const keep = if (index < b.start or index > b.end) true else switch (choice) {
            .ours => index >= b.ours[0] and index < b.ours[1],
            .theirs => index >= b.theirs[0] and index < b.theirs[1],
            .both => (index >= b.ours[0] and index < b.ours[1]) or (index >= b.theirs[0] and index < b.theirs[1]),
        };
        if (!keep) continue;
        if (!first) try out.append(gpa, '\n');
        try out.appendSlice(gpa, line);
        first = false;
    }
    return out.toOwnedSlice(gpa);
}

/// The first line (1-based) that is still a conflict marker; null: none.
pub fn firstMarker(text: []const u8) ?usize {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var index: usize = 1;
    while (lines.next()) |line| : (index += 1) {
        if (marker(line, '<') or marker(line, '>') or marker(line, '|') or marker(line, '=')) return index;
    }
    return null;
}

/// Saves `text` over `path` (relative to `repo`) and stages it. Null on
/// success; else why not (a marker left, git's message). Caller frees.
pub fn markResolved(gpa: std.mem.Allocator, registry: *workspace.Registry, repo: []const u8, path: []const u8, text: []const u8) !?[]u8 {
    if (firstMarker(text)) |line| {
        return try std.fmt.allocPrint(gpa, "{s} {d}", .{ language.t("A conflict marker is still on line", "Ainda há um marcador de conflito na linha"), line });
    }
    var buf: workspace.paths.Buffer = undefined;
    const full = try fs.join(&buf, repo, path);
    var real_buf: workspace.paths.Buffer = undefined;
    const real = try registry.resolve(full, &real_buf);
    const mode: u32 = if (fs.info(real, true)) |found| found.mode else 0o644;
    var tmp_buf: workspace.paths.Buffer = undefined;
    var name_buf: [workspace.paths.max_path]u8 = undefined;
    const dir = std.fs.path.dirname(real) orelse return error.NameInvalid;
    const name = std.fmt.bufPrint(&name_buf, ".{s}.cadex-resolve-{d}", .{ std.fs.path.basename(real), fs.processId() }) catch return error.NameTooLong;
    try fs.writeThenRename(try fs.join(&tmp_buf, dir, name), real, text, mode);
    var r = try git.run(gpa, registry, repo, &.{ "add", "--", path }, .{});
    defer r.deinit(gpa);
    if (r.ok()) return null;
    return try gpa.dupe(u8, git.message(r));
}

const testing = std.testing;

test "blocks with and without the base, resolved each way, and the marker left" {
    const gpa = testing.allocator;
    const text = "a\n<<<<<<< HEAD\nours\n||||||| base\nold\n=======\ntheirs\n>>>>>>> other\nb\n<<<<<<< HEAD\nx\n=======\ny\n>>>>>>> other\n";
    const all = try blocks(gpa, text);
    defer gpa.free(all);
    try testing.expectEqual(@as(usize, 2), all.len);
    try testing.expectEqual(@as(usize, 1), all[0].start);
    try testing.expectEqual([2]usize{ 4, 5 }, all[0].base.?);
    try testing.expect(all[1].base == null);
    const ours = try resolve(gpa, text, 0, .ours);
    defer gpa.free(ours);
    try testing.expectEqualStrings("a\nours\nb\n<<<<<<< HEAD\nx\n=======\ny\n>>>>>>> other\n", ours);
    try testing.expectEqual(@as(?usize, 4), firstMarker(ours));
    const both = try resolve(gpa, ours, 0, .both);
    defer gpa.free(both);
    try testing.expectEqualStrings("a\nours\nb\nx\ny\n", both);
    try testing.expect(firstMarker(both) == null);
    // A line of seven '=' in the code with text after is not a marker.
    try testing.expect(firstMarker("=======x\n<<<<<<<<\n") == null);
}
