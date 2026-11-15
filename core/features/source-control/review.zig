//! The review's diff (docs/spec/source-control.md, Diff contra base; plan
//! 21): a worktree against a base, everything since it (committed, staged,
//! unstaged and new files), or two tips against each other (two worktrees'
//! branches, for comparing tries of one task). The base by default is where
//! the task left its start branch: New Task (plan 19) keeps the branch's
//! name, not a commit, so the merge-base stays right when the branch moves.

const std = @import("std");
const workspace = @import("../workspace/workspace.zig");
const git = @import("git.zig");
const diff = @import("diff.zig");

const Registry = workspace.Registry;

/// The base commit (full sha): the merge-base of HEAD with `start` (the
/// task's start branch); without it, or when it is gone, with the default
/// branch (origin's HEAD, else main, else master). Null: none found (a
/// repository with one branch and no remote, or no commit). Caller frees.
pub fn defaultBase(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8, start: []const u8) !?[]u8 {
    if (start.len > 0) if (try mergeBase(gpa, registry, repo, start)) |sha| return sha;
    var head = try git.run(gpa, registry, repo, &.{ "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD" }, .{});
    defer head.deinit(gpa);
    if (head.ok()) if (try mergeBase(gpa, registry, repo, std.mem.trimEnd(u8, head.stdout, "\n"))) |sha| return sha;
    for ([_][]const u8{ "main", "master" }) |name| if (try mergeBase(gpa, registry, repo, name)) |sha| return sha;
    return null;
}

fn mergeBase(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8, ref: []const u8) !?[]u8 {
    if (!safeRef(ref)) return null;
    var r = try git.run(gpa, registry, repo, &.{ "merge-base", "HEAD", ref }, .{});
    defer r.deinit(gpa);
    if (!r.ok()) return null;
    return try gpa.dupe(u8, std.mem.trimEnd(u8, r.stdout, "\n"));
}

/// A commit or branch name the app passes on: never an option to git.
pub fn safeRef(ref: []const u8) bool {
    return ref.len > 0 and ref[0] != '-' and std.mem.indexOfAny(u8, ref, " \t\n\x00") == null;
}

/// The changed files, one line each: "status \t added \t removed \t path \t
/// orig" (status A, M, D, R, T or ? for a new file git does not know;
/// added and removed "-" for a binary). `to` null: the work tree, with the
/// new files; else a commit or branch (two tips). Caller frees.
pub fn files(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8, base: []const u8, to: ?[]const u8) ![]u8 {
    if (!safeRef(base)) return error.InvalidPattern;
    if (to) |t| if (!safeRef(t)) return error.InvalidPattern;
    const names = try range(gpa, registry, repo, base, to, "--name-status");
    defer gpa.free(names);
    const counts = try range(gpa, registry, repo, base, to, "--numstat");
    defer gpa.free(counts);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try join(gpa, &out, names, counts);
    if (to == null) try untracked(gpa, registry, repo, &out);
    return out.toOwnedSlice(gpa);
}

/// `git diff -M -z <flag> base [to]`, stdout. Caller frees.
fn range(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8, base: []const u8, to: ?[]const u8, flag: []const u8) ![]u8 {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(gpa);
    try args.appendSlice(gpa, &.{ "diff", "-M", "-z", "--no-color", "--no-ext-diff", flag, base });
    if (to) |t| try args.append(gpa, t);
    try args.append(gpa, "--");
    var r = try git.run(gpa, registry, repo, args.items, .{});
    gpa.free(r.stderr);
    if (!r.ok()) {
        gpa.free(r.stdout);
        return error.IoFailed;
    }
    return r.stdout;
}

/// Pairs `--name-status -z` (status, then one path or, renamed, two) with
/// `--numstat -z` (counts, then the path, or empty and the two paths), in
/// the same order git gives both.
fn join(gpa: std.mem.Allocator, out: *std.ArrayList(u8), names: []const u8, counts: []const u8) !void {
    var n = std.mem.splitScalar(u8, names, 0);
    var c = std.mem.splitScalar(u8, counts, 0);
    while (n.next()) |status| {
        if (status.len == 0) break;
        const renamed = status[0] == 'R' or status[0] == 'C';
        const first = n.next() orelse break;
        const second = if (renamed) n.next() orelse break else "";
        const stat = c.next() orelse "";
        if (renamed) {
            _ = c.next();
            _ = c.next();
        }
        var fields = std.mem.splitScalar(u8, stat, '\t');
        const added = fields.next() orelse "-";
        const removed = fields.next() orelse "-";
        const path = if (renamed) second else first;
        const orig = if (renamed) first else "";
        try out.print(gpa, "{c}\t{s}\t{s}\t{s}\t{s}\n", .{ status[0], added, removed, path, orig });
    }
}

/// The work tree's files git does not know (ignored ones left out), with
/// their line count (a binary or too big file: "-").
fn untracked(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8, out: *std.ArrayList(u8)) !void {
    var r = try git.run(gpa, registry, repo, &.{ "ls-files", "--others", "--exclude-standard", "-z" }, .{});
    defer r.deinit(gpa);
    if (!r.ok()) return;
    var it = std.mem.splitScalar(u8, r.stdout, 0);
    while (it.next()) |path| {
        if (path.len == 0) continue;
        const text = try diff.readDisk(gpa, registry, repo, path);
        defer gpa.free(text);
        if (diff.isBinary(text) or text.len >= diff.max_side_bytes) {
            try out.print(gpa, "?\t-\t0\t{s}\t\n", .{path});
        } else {
            const lines = std.mem.count(u8, text, "\n") + @intFromBool(text.len > 0 and text[text.len - 1] != '\n');
            try out.print(gpa, "?\t{d}\t0\t{s}\t\n", .{ lines, path });
        }
    }
}

/// One file against the base: the base's version, the work tree's (or
/// `to`'s) and the patch, with the same limits as the panel's diff.
pub fn fileSides(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8, base: []const u8, to: ?[]const u8, path: []const u8, orig: []const u8) !diff.Sides {
    if (!safeRef(base)) return error.InvalidPattern;
    if (to) |t| if (!safeRef(t)) return error.InvalidPattern;
    const before = try diff.show(gpa, registry, repo, base, if (orig.len > 0) orig else path);
    errdefer gpa.free(before);
    const after = if (to) |t| try diff.show(gpa, registry, repo, t, path) else try diff.readDisk(gpa, registry, repo, path);
    errdefer gpa.free(after);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(gpa);
    try args.appendSlice(gpa, &.{ "diff", "-M", "--no-color", "--no-ext-diff", base });
    if (to) |t| try args.append(gpa, t);
    try args.append(gpa, "--");
    if (orig.len > 0) try args.append(gpa, orig);
    try args.append(gpa, path);
    var r = try git.run(gpa, registry, repo, args.items, .{});
    errdefer r.deinit(gpa);
    gpa.free(r.stderr);
    r.stderr = &.{};
    // A file git does not know has no patch against the base: every line is new.
    if (r.stdout.len == 0 and before.len == 0 and after.len > 0) {
        gpa.free(r.stdout);
        r.stdout = try newFilePatch(gpa, path, after);
    }
    const binary = diff.isBinary(before) or diff.isBinary(after);
    const too_large = before.len > diff.max_side_bytes or after.len > diff.max_side_bytes;
    return .{ .before = before, .after = after, .patch = r.stdout, .binary = binary, .too_large = too_large };
}

fn newFilePatch(gpa: std.mem.Allocator, path: []const u8, text: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const body = std.mem.trimEnd(u8, text, "\n");
    const count = std.mem.count(u8, body, "\n") + 1;
    try out.print(gpa, "diff --git a/{s} b/{s}\nnew file mode 100644\n--- /dev/null\n+++ b/{s}\n@@ -0,0 +1,{d} @@\n", .{ path, path, path, count });
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |line| try out.print(gpa, "+{s}\n", .{line});
    if (text[text.len - 1] != '\n') try out.appendSlice(gpa, "\\ No newline at end of file\n");
    return out.toOwnedSlice(gpa);
}
