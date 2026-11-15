//! The review's diff and partial staging on real temporary repositories
//! (plan 21, phase B1): a task's worktree against where it left main, two
//! tips against each other, and some lines in and out of the index.

const std = @import("std");
const testing = std.testing;
const workspace = @import("../workspace/workspace.zig");
const git = @import("git.zig");
const review = @import("review.zig");
const partial = @import("partial.zig");
const TestDir = @import("../../shared/test_dir.zig").TestDir;
const repo_test = @import("repo_test.zig");
const sh = repo_test.sh;

/// git's output in `repo`, owned.
fn out(registry: *workspace.Registry, repo: []const u8, args: []const []const u8) ![]u8 {
    const r = try git.run(testing.allocator, registry, repo, args, .{});
    testing.allocator.free(r.stderr);
    return r.stdout;
}

fn expectHas(text: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, text, needle) == null) {
        std.debug.print("missing {s} in:\n{s}\n", .{ needle, text });
        return error.Missing;
    }
}

/// main with a.txt and r.txt committed; a task worktree `wt` on branch task.
fn taskRepo(dir: *TestDir, registry: *workspace.Registry, repo_buf: []u8, wt_buf: []u8) !struct { []const u8, []const u8 } {
    const repo = try repo_test.newRepo(dir, registry, "repo", repo_buf);
    try dir.writeFile("repo/a.txt", "one\ntwo\nthree\n");
    try dir.writeFile("repo/r.txt", "kept\n");
    try sh(registry, repo, &.{ "add", "." });
    try sh(registry, repo, &.{ "commit", "-q", "-m", "start" });
    const wt = try dir.joinInto(wt_buf, "wt");
    try sh(registry, repo, &.{ "worktree", "add", "-q", "-b", "task", wt, "main" });
    return .{ repo, wt };
}

test "a task's worktree against where it left main: committed, staged, unstaged, renamed and new" {
    var dir = try TestDir.init();
    defer dir.deinit();
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize(dir.path());
    var repo_buf: [1024]u8 = undefined;
    var wt_buf: [1024]u8 = undefined;
    const repo, const wt = try taskRepo(&dir, &registry, &repo_buf, &wt_buf);
    const fork = try out(&registry, repo, &.{ "rev-parse", "main" });
    defer testing.allocator.free(fork);

    // The task: a commit, a staged rename, an unstaged edit and a new file.
    try dir.writeFile("wt/a.txt", "one\nTWO\nthree\n");
    try sh(&registry, wt, &.{ "commit", "-q", "-am", "agent" });
    try sh(&registry, wt, &.{ "mv", "r.txt", "renamed.txt" });
    try dir.writeFile("wt/a.txt", "one\nTWO\nthree\nfour\n");
    try dir.writeFile("wt/new.txt", "n1\nn2\n");
    // main moves on: the base stays where the task left it.
    try dir.writeFile("repo/later.txt", "x\n");
    try sh(&registry, repo, &.{ "add", "." });
    try sh(&registry, repo, &.{ "commit", "-q", "-m", "later" });

    const base = (try review.defaultBase(testing.allocator, &registry, wt, "main")).?;
    defer testing.allocator.free(base);
    try testing.expectEqualStrings(std.mem.trimEnd(u8, fork, "\n"), base);
    const without = (try review.defaultBase(testing.allocator, &registry, wt, "")).?;
    defer testing.allocator.free(without);
    try testing.expectEqualStrings(base, without);

    const list = try review.files(testing.allocator, &registry, wt, base, null);
    defer testing.allocator.free(list);
    try expectHas(list, "M\t2\t1\ta.txt\t\n");
    try expectHas(list, "R\t0\t0\trenamed.txt\tr.txt\n");
    try expectHas(list, "?\t2\t0\tnew.txt\t\n");
    try testing.expect(std.mem.indexOf(u8, list, "later.txt") == null);

    var a = try review.fileSides(testing.allocator, &registry, wt, base, null, "a.txt", "");
    defer a.deinit(testing.allocator);
    try testing.expectEqualStrings("one\ntwo\nthree\n", a.before);
    try testing.expectEqualStrings("one\nTWO\nthree\nfour\n", a.after);
    try expectHas(a.patch, "-two\n+TWO\n three\n+four\n");
    var n = try review.fileSides(testing.allocator, &registry, wt, base, null, "new.txt", "");
    defer n.deinit(testing.allocator);
    try expectHas(n.patch, "@@ -0,0 +1,2 @@\n+n1\n+n2\n");

    try testing.expectError(error.InvalidPattern, review.files(testing.allocator, &registry, wt, "--output=x", null));
}

test "two tips against each other: what differs between two tries" {
    var dir = try TestDir.init();
    defer dir.deinit();
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize(dir.path());
    var repo_buf: [1024]u8 = undefined;
    var wt_buf: [1024]u8 = undefined;
    const repo, const wt = try taskRepo(&dir, &registry, &repo_buf, &wt_buf);
    try dir.writeFile("wt/a.txt", "one\nfirst try\nthree\n");
    try sh(&registry, wt, &.{ "commit", "-q", "-am", "try 1" });
    var other_buf: [1024]u8 = undefined;
    const other = try dir.joinInto(&other_buf, "wt2");
    try sh(&registry, repo, &.{ "worktree", "add", "-q", "-b", "task2", other, "main" });
    try dir.writeFile("wt2/a.txt", "one\nsecond try\nthree\n");
    try sh(&registry, other, &.{ "commit", "-q", "-am", "try 2" });

    const list = try review.files(testing.allocator, &registry, repo, "task", "task2");
    defer testing.allocator.free(list);
    try testing.expectEqualStrings("M\t1\t1\ta.txt\t\n", list);
    var a = try review.fileSides(testing.allocator, &registry, repo, "task", "task2", "a.txt", "");
    defer a.deinit(testing.allocator);
    try expectHas(a.patch, "-first try\n+second try\n");
}

test "partial staging: one line in, then out again; one line of a new file" {
    var dir = try TestDir.init();
    defer dir.deinit();
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize(dir.path());
    var repo_buf: [1024]u8 = undefined;
    var wt_buf: [1024]u8 = undefined;
    _, const wt = try taskRepo(&dir, &registry, &repo_buf, &wt_buf);
    try dir.writeFile("wt/a.txt", "one\nTWO\nthree\nfour\n");

    const patch = try partial.patchOf(testing.allocator, &registry, wt, "a.txt", false);
    defer testing.allocator.free(patch);
    const four = lineIndex(patch, "+four").?;
    try repo_test.expectNoError(try partial.apply(testing.allocator, &registry, wt, patch, &.{four}, false));
    const cached = try out(&registry, wt, &.{ "diff", "--cached", "--", "a.txt" });
    defer testing.allocator.free(cached);
    try expectHas(cached, " three\n+four\n");
    try testing.expect(std.mem.indexOf(u8, cached, "+TWO") == null);
    const left = try out(&registry, wt, &.{ "diff", "--", "a.txt" });
    defer testing.allocator.free(left);
    try expectHas(left, "-two\n+TWO\n");

    const staged = try partial.patchOf(testing.allocator, &registry, wt, "a.txt", true);
    defer testing.allocator.free(staged);
    try repo_test.expectNoError(try partial.apply(testing.allocator, &registry, wt, staged, &.{lineIndex(staged, "+four").?}, true));
    const none = try out(&registry, wt, &.{ "diff", "--cached", "--", "a.txt" });
    defer testing.allocator.free(none);
    try testing.expectEqualStrings("", none);

    try dir.writeFile("wt/fresh.txt", "l1\nl2\nl3\n");
    const fresh = try partial.patchOf(testing.allocator, &registry, wt, "fresh.txt", false);
    defer testing.allocator.free(fresh);
    try repo_test.expectNoError(try partial.apply(testing.allocator, &registry, wt, fresh, &.{lineIndex(fresh, "+l1").?}, false));
    const index = try out(&registry, wt, &.{ "show", ":fresh.txt" });
    defer testing.allocator.free(index);
    try testing.expectEqualStrings("l1\n", index);
}

fn lineIndex(patch: []const u8, line: []const u8) ?usize {
    var it = std.mem.splitScalar(u8, patch, '\n');
    var i: usize = 0;
    while (it.next()) |l| : (i += 1) if (std.mem.eql(u8, l, line)) return i;
    return null;
}
