//! git-history on a real temporary repository with two merges: the log in
//! pages, the search, a commit's files, a file's diff in a commit and the
//! address on the remote.

const std = @import("std");
const testing = std.testing;
const workspace = @import("../workspace/workspace.zig");
const sc = @import("../source-control/source_control.zig");
const log = @import("log.zig");
const details = @import("details.zig");
const remote = @import("remote.zig");
const TestDir = @import("../../shared/test_dir.zig").TestDir;

fn sh(registry: *workspace.Registry, repo: []const u8, args: []const []const u8) !void {
    var r = try sc.git.run(testing.allocator, registry, repo, args, .{});
    defer r.deinit(testing.allocator);
    if (!r.ok()) {
        std.debug.print("git {s}: {s}\n", .{ args[0], r.stderr });
        return error.GitFailed;
    }
}

fn commitFile(dir: *TestDir, registry: *workspace.Registry, repo: []const u8, name: []const u8, text: []const u8) !void {
    var buf: [256]u8 = undefined;
    try dir.writeFile(try std.fmt.bufPrint(&buf, "repo/{s}", .{name}), text);
    try sh(registry, repo, &.{ "add", "--", name });
    try sh(registry, repo, &.{ "commit", "--quiet", "-m", name });
}

/// A <- B <- D(B, C) <- E <- G(E, F), with C on feature and F on other.
fn twoMerges(dir: *TestDir, registry: *workspace.Registry, buf: []u8) ![]const u8 {
    try dir.makeDir("repo");
    const repo = try dir.joinInto(buf, "repo");
    try sh(registry, repo, &.{ "init", "--quiet", "--initial-branch=main" });
    try sh(registry, repo, &.{ "config", "user.name", "Ana" });
    try sh(registry, repo, &.{ "config", "user.email", "ana@cadex" });
    try commitFile(dir, registry, repo, "a.txt", "a\n");
    try sh(registry, repo, &.{ "switch", "--quiet", "-c", "feature" });
    try commitFile(dir, registry, repo, "c.txt", "c\n");
    try sh(registry, repo, &.{ "switch", "--quiet", "main" });
    try commitFile(dir, registry, repo, "b.txt", "b\n");
    try sh(registry, repo, &.{ "merge", "--quiet", "--no-ff", "-m", "merge feature", "feature" });
    try sh(registry, repo, &.{ "switch", "--quiet", "-c", "other" });
    try commitFile(dir, registry, repo, "f.txt", "f\n");
    try sh(registry, repo, &.{ "switch", "--quiet", "main" });
    try commitFile(dir, registry, repo, "a.txt", "a\nmais\n");
    try sh(registry, repo, &.{ "merge", "--quiet", "--no-ff", "-m", "merge other", "other" });
    return repo;
}

fn countLines(text: []const u8) usize {
    return std.mem.count(u8, text, "\n");
}

fn field(line: []const u8, index: usize) []const u8 {
    var it = std.mem.splitScalar(u8, line, '\t');
    var i: usize = 0;
    while (it.next()) |f| : (i += 1) if (i == index) return f;
    return "";
}

test "the log in pages has parents, refs and a graph that ends at the root" {
    var dir = try TestDir.init();
    defer dir.deinit();
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize(dir.path());
    var buf: [1024]u8 = undefined;
    const repo = try twoMerges(&dir, &registry, &buf);

    var l = try log.Log.init(testing.allocator, &registry, repo, "", false);
    defer l.deinit();
    const first = try l.next(3);
    defer testing.allocator.free(first);
    const rest = try l.next(100);
    defer testing.allocator.free(rest);
    const after = try l.next(100);
    defer testing.allocator.free(after);
    try testing.expectEqual(@as(usize, 3), countLines(first));
    try testing.expectEqual(@as(usize, 4), countLines(rest));
    try testing.expectEqual(@as(usize, 0), after.len);

    const top = first[0..std.mem.indexOfScalar(u8, first, '\n').?];
    try testing.expectEqualStrings("merge other", field(top, 6));
    try testing.expectEqual(@as(usize, 2), std.mem.count(u8, field(top, 1), " ") + 1);
    try testing.expect(std.mem.indexOf(u8, field(top, 5), "HEAD -> main") != null);
    try testing.expectEqualStrings("Ana", field(top, 2));
    try testing.expectEqualStrings("0", field(top, 7));
    // The root is last, has no parents, and closes every lane.
    var lines = std.mem.splitBackwardsScalar(u8, std.mem.trimEnd(u8, rest, "\n"), '\n');
    const root = lines.next().?;
    try testing.expectEqualStrings("a.txt", field(root, 6));
    try testing.expectEqualStrings("", field(root, 1));
    try testing.expectEqualStrings("", field(root, 10));
    try testing.expectEqual(@as(usize, 0), l.lanes.lanes.items.len);
}

test "search, current branch only, details, a diff in a commit and the remote" {
    var dir = try TestDir.init();
    defer dir.deinit();
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize(dir.path());
    var buf: [1024]u8 = undefined;
    const repo = try twoMerges(&dir, &registry, &buf);

    var found = try log.Log.init(testing.allocator, &registry, repo, "MERGE", false);
    defer found.deinit();
    const matches = try found.next(1);
    defer testing.allocator.free(matches);
    try testing.expectEqual(@as(usize, 1), countLines(matches));
    try testing.expectEqualStrings("-1", field(matches, 7));
    const more = try found.next(10);
    defer testing.allocator.free(more);
    try testing.expectEqual(@as(usize, 1), countLines(more));

    // Off another branch, HEAD reaches less.
    try sh(&registry, repo, &.{ "switch", "--quiet", "feature" });
    var current = try log.Log.init(testing.allocator, &registry, repo, "", true);
    defer current.deinit();
    const feature = try current.next(100);
    defer testing.allocator.free(feature);
    try testing.expectEqual(@as(usize, 2), countLines(feature));
    try sh(&registry, repo, &.{ "switch", "--quiet", "main" });

    // The last merge against its first parent brings f.txt.
    var head = try sc.git.run(testing.allocator, &registry, repo, &.{ "rev-parse", "HEAD" }, .{});
    defer head.deinit(testing.allocator);
    const sha = std.mem.trimEnd(u8, head.stdout, "\n");
    const info = try details.read(testing.allocator, &registry, repo, sha);
    defer testing.allocator.free(info);
    try testing.expect(std.mem.indexOf(u8, info, "merge other\n") != null);
    try testing.expect(std.mem.endsWith(u8, info, "\x1eA\t1\t0\tf.txt\t\n"));

    var parent = try sc.git.run(testing.allocator, &registry, repo, &.{ "rev-parse", "HEAD^1" }, .{});
    defer parent.deinit(testing.allocator);
    var sides = try sc.diff.commitSides(testing.allocator, &registry, repo, std.mem.trimEnd(u8, parent.stdout, "\n"), "a.txt", "");
    defer sides.deinit(testing.allocator);
    try testing.expectEqualStrings("a\n", sides.before);
    try testing.expectEqualStrings("a\nmais\n", sides.after);
    try testing.expect(std.mem.indexOf(u8, sides.patch, "+mais") != null);

    const none = try remote.originCommitUrl(testing.allocator, &registry, repo, sha);
    try testing.expect(none == null);
    try sh(&registry, repo, &.{ "remote", "add", "origin", "git@github.com:ana/cadex.git" });
    const url = (try remote.originCommitUrl(testing.allocator, &registry, repo, sha)).?;
    defer testing.allocator.free(url);
    try testing.expect(std.mem.startsWith(u8, url, "https://github.com/ana/cadex/commit/"));
}
