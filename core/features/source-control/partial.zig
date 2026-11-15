//! Stage and unstage of some lines of a file (docs/spec/source-control.md,
//! Stage parcial; plan 21): the app picks lines of the file's patch (the
//! unstaged one to stage, the staged one to unstage) by their index in the
//! patch text; the core keeps only those changes and hands the rest to
//! `git apply --cached`, never touching the disk. A new file is first made
//! known to git with `add -N`, so its patch exists and only the chosen
//! lines enter (checked with git 2.50, 2026-11-15).

const std = @import("std");
const workspace = @import("../workspace/workspace.zig");
const git = @import("git.zig");

const Registry = workspace.Registry;

/// The patch with only the changes at `chosen` (indices of lines of
/// `patch`, split on '\n'). Staging (`reverse` false): an unchosen `+`
/// line is dropped and an unchosen `-` line stays as context. Unstaging
/// (the staged patch applied in reverse): an unchosen `-` line is dropped
/// and an unchosen `+` line stays as context, since it stays in the index.
/// Hunks left with no change go; null when nothing is left. Caller frees.
pub fn filter(gpa: std.mem.Allocator, patch: []const u8, chosen: []const usize, reverse: bool) !?[]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var hunk: std.ArrayList(u8) = .empty;
    defer hunk.deinit(gpa);
    var header: []const u8 = "";
    var in_hunk = false;
    var changes: usize = 0;
    var kept_any = false;
    var lines = std.mem.splitScalar(u8, patch, '\n');
    var index: usize = 0;
    while (lines.next()) |line| : (index += 1) {
        if (std.mem.startsWith(u8, line, "@@")) {
            kept_any = try flush(gpa, &out, header, &hunk, changes) or kept_any;
            header = line;
            changes = 0;
            in_hunk = true;
            continue;
        }
        if (!in_hunk) {
            if (line.len > 0) try out.print(gpa, "{s}\n", .{line});
            continue;
        }
        if (line.len == 0) continue;
        const picked = contains(chosen, index);
        switch (line[0]) {
            '+', '-' => {
                const keeps_as_change = picked;
                const drop = if (line[0] == '+') !reverse else reverse;
                if (keeps_as_change) {
                    try hunk.print(gpa, "{s}\n", .{line});
                    changes += 1;
                } else if (!drop) {
                    try hunk.print(gpa, " {s}\n", .{line[1..]});
                }
            },
            // Context, and "\ No newline at end of file".
            else => try hunk.print(gpa, "{s}\n", .{line}),
        }
    }
    kept_any = try flush(gpa, &out, header, &hunk, changes) or kept_any;
    if (!kept_any) {
        out.deinit(gpa);
        return null;
    }
    return try out.toOwnedSlice(gpa);
}

/// Writes a hunk that kept a change (the counts are recomputed by
/// `git apply --recount`); true when it did.
fn flush(gpa: std.mem.Allocator, out: *std.ArrayList(u8), header: []const u8, hunk: *std.ArrayList(u8), changes: usize) !bool {
    defer hunk.clearRetainingCapacity();
    if (header.len == 0 or changes == 0) return false;
    try out.print(gpa, "{s}\n", .{header});
    try out.appendSlice(gpa, hunk.items);
    return true;
}

fn contains(list: []const usize, value: usize) bool {
    return std.mem.indexOfScalar(usize, list, value) != null;
}

/// Stages (or, `reverse`, unstages) the lines `chosen` of `patch`, the
/// file's patch as the app showed it. Null on success, else git's message.
pub fn apply(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8, patch: []const u8, chosen: []const usize, reverse: bool) !?[]u8 {
    const kept = try filter(gpa, patch, chosen, reverse) orelse return null;
    defer gpa.free(kept);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(gpa);
    try args.appendSlice(gpa, &.{ "apply", "--cached", "--recount", "--whitespace=nowarn" });
    if (reverse) try args.append(gpa, "--reverse");
    try args.append(gpa, "-");
    var r = try git.run(gpa, registry, repo, args.items, .{ .stdin = kept });
    defer r.deinit(gpa);
    if (r.ok()) return null;
    return try gpa.dupe(u8, git.message(r));
}

/// The patch to pick lines from: the unstaged one (`staged` false) or the
/// staged one. A path git does not know yet is made known first (`add
/// -N`), so its patch shows every line as added. Caller frees.
pub fn patchOf(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8, path: []const u8, staged: bool) ![]u8 {
    if (!staged and !try tracked(gpa, registry, repo, path)) {
        var add = try git.run(gpa, registry, repo, &.{ "add", "-N", "--", path }, .{});
        add.deinit(gpa);
    }
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(gpa);
    try args.appendSlice(gpa, &.{ "diff", "--no-color", "--no-ext-diff" });
    if (staged) try args.append(gpa, "--cached");
    try args.appendSlice(gpa, &.{ "--", path });
    const r = try git.run(gpa, registry, repo, args.items, .{});
    gpa.free(r.stderr);
    return r.stdout;
}

fn tracked(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8, path: []const u8) !bool {
    var r = try git.run(gpa, registry, repo, &.{ "ls-files", "--error-unmatch", "--", path }, .{});
    defer r.deinit(gpa);
    return r.ok();
}

test "filter keeps the chosen changes, turns the rest into context or drops it" {
    const gpa = std.testing.allocator;
    const patch =
        \\diff --git a/f b/f
        \\--- a/f
        \\+++ b/f
        \\@@ -1,3 +1,3 @@
        \\ a
        \\-b
        \\+B
        \\ c
        \\@@ -10,2 +10,3 @@
        \\ x
        \\+y
        \\ z
        \\
    ;
    // Line 6 is "+B": staging only it keeps "-b" as context.
    const staged = (try filter(gpa, patch, &.{6}, false)).?;
    defer gpa.free(staged);
    try std.testing.expectEqualStrings("diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1,3 +1,3 @@\n a\n b\n+B\n c\n", staged);
    // Unstaging only "-b" drops nothing else that changes: "+B" becomes context.
    const back = (try filter(gpa, patch, &.{5}, true)).?;
    defer gpa.free(back);
    try std.testing.expectEqualStrings("diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1,3 +1,3 @@\n a\n-b\n B\n c\n", back);
    try std.testing.expect(try filter(gpa, patch, &.{}, false) == null);
}
