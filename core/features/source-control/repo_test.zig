//! source-control on real temporary repositories: status, stage, unstage,
//! commit, diff, branches, and pull refusing what is not a fast-forward.

const std = @import("std");
const testing = std.testing;
const workspace = @import("../workspace/workspace.zig");
const git = @import("git.zig");
const status = @import("status.zig");
const actions = @import("actions.zig");
const diff = @import("diff.zig");
const TestDir = @import("../../shared/test_dir.zig").TestDir;

/// Runs git in `repo` and expects it to work.
fn sh(registry: *workspace.Registry, repo: []const u8, args: []const []const u8) !void {
    var r = try git.run(testing.allocator, registry, repo, args, .{});
    defer r.deinit(testing.allocator);
    if (!r.ok()) {
        std.debug.print("git {s}: {s}\n", .{ args[0], r.stderr });
        return error.GitFailed;
    }
}

fn newRepo(dir: *TestDir, registry: *workspace.Registry, sub: []const u8, buf: []u8) ![]const u8 {
    try dir.makeDir(sub);
    const repo = try dir.joinInto(buf, sub);
    try sh(registry, repo, &.{ "init", "--quiet", "--initial-branch=main" });
    try sh(registry, repo, &.{ "config", "user.name", "Teste" });
    try sh(registry, repo, &.{ "config", "user.email", "teste@cadex" });
    return repo;
}

fn expectNoError(err: ?[]u8) !void {
    if (err) |e| {
        defer testing.allocator.free(e);
        std.debug.print("unexpected: {s}\n", .{e});
        return error.Unexpected;
    }
}

test "status, stage, commit, unstage and diff on a real repository" {
    var dir = try TestDir.init();
    defer dir.deinit();
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize(dir.path());
    var repo_buf: [1024]u8 = undefined;
    const repo = try newRepo(&dir, &registry, "repo", &repo_buf);
    try testing.expect(git.available(testing.allocator));
    const top = (try git.root(testing.allocator, &registry, repo)).?;
    defer testing.allocator.free(top);
    try testing.expectEqualStrings(repo, top);

    try dir.writeFile("repo/nome com espaço.txt", "um\ndois\n");
    var s1 = try status.read(testing.allocator, &registry, repo);
    defer s1.deinit();
    try testing.expectEqualStrings("main", s1.branch);
    try testing.expectEqual(@as(usize, 1), s1.entries.len);
    try testing.expectEqual(status.Kind.untracked, s1.entries[0].kind);

    try expectNoError(try actions.stage(testing.allocator, &registry, repo, &.{"nome com espaço.txt"}));
    try expectNoError(try actions.unstage(testing.allocator, &registry, repo, &.{"nome com espaço.txt"}));
    try expectNoError(try actions.commit(testing.allocator, &registry, repo, "primeiro", true));
    var s2 = try status.read(testing.allocator, &registry, repo);
    defer s2.deinit();
    try testing.expectEqual(@as(usize, 0), s2.entries.len);

    try dir.writeFile("repo/nome com espaço.txt", "um\nTRÊS\n");
    var d = try diff.sides(testing.allocator, &registry, repo, "nome com espaço.txt", "", false);
    defer d.deinit(testing.allocator);
    try testing.expectEqualStrings("um\ndois\n", d.before);
    try testing.expectEqualStrings("um\nTRÊS\n", d.after);
    try testing.expect(std.mem.indexOf(u8, d.patch, "+TRÊS") != null);
    try testing.expect(!d.binary);

    try sh(&registry, repo, &.{ "mv", "nome com espaço.txt", "novo.txt" });
    var s3 = try status.read(testing.allocator, &registry, repo);
    defer s3.deinit();
    try testing.expectEqual(status.Kind.renamed, s3.entries[0].kind);
    try testing.expectEqualStrings("nome com espaço.txt", s3.entries[0].orig);

    const empty = try actions.commit(testing.allocator, &registry, repo, "  ", false);
    try testing.expect(empty != null);
    testing.allocator.free(empty.?);
}

test "pull refuses to merge diverged branches; branches are listed" {
    var dir = try TestDir.init();
    defer dir.deinit();
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize(dir.path());
    var origin_buf: [1024]u8 = undefined;
    const origin = try newRepo(&dir, &registry, "origin", &origin_buf);
    try dir.writeFile("origin/a.txt", "a\n");
    try expectNoError(try actions.commit(testing.allocator, &registry, origin, "a", true));
    try sh(&registry, dir.path(), &.{ "clone", "--quiet", "origin", "clone" });
    var clone_buf: [1024]u8 = undefined;
    const clone = try dir.joinInto(&clone_buf, "clone");
    try sh(&registry, clone, &.{ "config", "user.name", "Teste" });
    try sh(&registry, clone, &.{ "config", "user.email", "teste@cadex" });

    try dir.writeFile("origin/b.txt", "b\n");
    try expectNoError(try actions.commit(testing.allocator, &registry, origin, "b no origin", true));
    try dir.writeFile("clone/c.txt", "c\n");
    try expectNoError(try actions.commit(testing.allocator, &registry, clone, "c no clone", true));
    try expectNoError(try actions.fetch(testing.allocator, &registry, clone));
    var s = try status.read(testing.allocator, &registry, clone);
    defer s.deinit();
    try testing.expectEqual(@as(u32, 1), s.ahead);
    try testing.expectEqual(@as(u32, 1), s.behind);
    const refused = (try actions.pull(testing.allocator, &registry, clone)).?;
    defer testing.allocator.free(refused);
    try testing.expectEqualStrings("The branches have diverged: merge or rebase in the terminal", refused);

    try sh(&registry, clone, &.{ "branch", "outra" });
    const list = try actions.branches(testing.allocator, &registry, clone);
    defer testing.allocator.free(list);
    try testing.expect(std.mem.startsWith(u8, list, "local\tmain\n"));
    try testing.expect(std.mem.indexOf(u8, list, "local\toutra\n") != null);
    try testing.expect(std.mem.indexOf(u8, list, "remote\torigin/main") == null);
    try expectNoError(try actions.switchTo(testing.allocator, &registry, clone, "outra", false));
}

test "git outside the workspace is refused" {
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    // A folder that exists on every system: the test's own temporary one.
    var dir = try TestDir.init();
    defer dir.deinit();
    try testing.expectError(error.Outside, git.run(testing.allocator, &registry, dir.path(), &.{"status"}, .{}));
}
