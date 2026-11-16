//! worktrees on real temporary repositories: the branch name, a task made
//! with its `.env` copied, the list, what would be lost, and taking it away.

const std = @import("std");
const testing = std.testing;
const workspace = @import("../workspace/workspace.zig");
const sc = @import("../source-control/source_control.zig");
const tasks = @import("tasks.zig");
const include = @import("include.zig");
const fs = @import("../../shared/fs.zig");
const TestDir = @import("../../shared/test_dir.zig").TestDir;

fn sh(registry: *workspace.Registry, repo: []const u8, args: []const []const u8) !void {
    var r = try sc.git.run(testing.allocator, registry, repo, args, .{});
    defer r.deinit(testing.allocator);
    if (!r.ok()) {
        std.debug.print("git {s}: {s}\n", .{ args[0], r.stderr });
        return error.GitFailed;
    }
}

test "a task's name becomes a branch" {
    const cases = [_][2][]const u8{ .{ "Corrigir login!", "corrigir-login" }, .{ "Ação no Pré-checkout", "acao-no-pre-checkout" }, .{ "!!!", "task" } };
    for (cases) |case| {
        const name = try tasks.branchName(testing.allocator, case[0]);
        defer testing.allocator.free(name);
        try testing.expectEqualStrings(case[1], name);
    }
}

test "a task: its worktree and branch, the .env copied, listed, what would be lost, taken away" {
    var dir = try TestDir.init();
    defer dir.deinit();
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize(dir.path());
    try dir.makeDir("repo");
    var repo_buf: [1024]u8 = undefined;
    const repo = try dir.joinInto(&repo_buf, "repo");
    try sh(&registry, repo, &.{ "init", "--quiet", "--initial-branch=main" });
    try sh(&registry, repo, &.{ "config", "user.name", "Teste" });
    try sh(&registry, repo, &.{ "config", "user.email", "teste@cadex" });
    try dir.writeFile("repo/app.txt", "um\n");
    try dir.writeFile("repo/.gitignore", ".env\nsecrets/\n");
    try dir.writeFile("repo/.worktreeinclude", ".env\nsecrets/\nmissing.key\n");
    try dir.writeFile("repo/.env", "TOKEN=x\n");
    try dir.makeDir("repo/secrets");
    try dir.writeFile("repo/secrets/a.pem", "pem\n");
    try sh(&registry, repo, &.{ "add", "app.txt", ".gitignore", ".worktreeinclude" });
    try sh(&registry, repo, &.{ "commit", "--quiet", "-m", "first" });

    try dir.makeDir("repo.worktrees");
    var path_buf: [1024]u8 = undefined;
    const path = try dir.joinInto(&path_buf, "repo.worktrees/corrigir-login");
    try testing.expect((try tasks.create(testing.allocator, &registry, repo, path, "corrigir-login", "main")) == null);

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const report = try include.copy(arena.allocator(), &registry, repo, path);
    try testing.expectEqual(@as(usize, 2), report.copied);
    try testing.expectEqualStrings("missing.key\n", report.unmatched);
    var env_buf: fs.Buffer = undefined;
    try testing.expect(fs.exists(try std.fmt.bufPrint(&env_buf, "{s}/.env", .{path})));
    try testing.expect(fs.exists(try std.fmt.bufPrint(&env_buf, "{s}/secrets/a.pem", .{path})));

    const list = try tasks.list(arena.allocator(), &registry, repo);
    try testing.expectEqual(@as(usize, 2), list.len);
    try testing.expectEqualStrings("corrigir-login", list[1].branch);

    // Its copied .env is ignored, not a change: nothing to lose yet.
    const clean = try tasks.whatWouldBeLost(testing.allocator, &registry, path, "corrigir-login");
    defer testing.allocator.free(clean);
    try testing.expectEqualStrings("", clean);
    try dir.writeFile("repo.worktrees/corrigir-login/app.txt", "dois\n");
    const changed = try tasks.whatWouldBeLost(testing.allocator, &registry, path, "corrigir-login");
    defer testing.allocator.free(changed);
    try testing.expectEqualStrings("app.txt\n", changed);
    const refused = (try tasks.remove(testing.allocator, &registry, repo, path, null)).?;
    defer testing.allocator.free(refused);
    try testing.expect(refused.len > 0);

    try sh(&registry, path, &.{ "commit", "--quiet", "-am", "fix" });
    const commit = try tasks.whatWouldBeLost(testing.allocator, &registry, path, "corrigir-login");
    defer testing.allocator.free(commit);
    try testing.expect(std.mem.startsWith(u8, commit, "commit ") and std.mem.indexOf(u8, commit, "fix") != null);

    // Merged into main, nothing is lost and it goes, branch and all.
    try sh(&registry, repo, &.{ "merge", "--quiet", "corrigir-login" });
    const merged = try tasks.whatWouldBeLost(testing.allocator, &registry, path, "corrigir-login");
    defer testing.allocator.free(merged);
    try testing.expectEqualStrings("", merged);
    try testing.expect((try tasks.remove(testing.allocator, &registry, repo, path, "corrigir-login")) == null);
    try testing.expect(!fs.exists(path));
}

test "a race's discard: the folder gone, prune forgets it, the branch stays until deleted" {
    var dir = try TestDir.init();
    defer dir.deinit();
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize(dir.path());
    try dir.makeDir("repo");
    var repo_buf: [1024]u8 = undefined;
    const repo = try dir.joinInto(&repo_buf, "repo");
    try sh(&registry, repo, &.{ "init", "--quiet", "--initial-branch=main" });
    try sh(&registry, repo, &.{ "config", "user.name", "Teste" });
    try sh(&registry, repo, &.{ "config", "user.email", "teste@cadex" });
    try dir.writeFile("repo/app.txt", "um\n");
    try sh(&registry, repo, &.{ "add", "app.txt" });
    try sh(&registry, repo, &.{ "commit", "--quiet", "-m", "first" });
    try dir.makeDir("repo.worktrees");
    var path_buf: [1024]u8 = undefined;
    const path = try dir.joinInto(&path_buf, "repo.worktrees/fix-2");
    try testing.expect((try tasks.create(testing.allocator, &registry, repo, path, "fix-2", "main")) == null);
    try dir.writeFile("repo.worktrees/fix-2/app.txt", "dois\n");
    try sh(&registry, path, &.{ "commit", "--quiet", "-am", "try 2" });

    // The app deletes the folder; here it is moved out of the way.
    var gone_buf: [1024]u8 = undefined;
    try fs.rename(path, try dir.joinInto(&gone_buf, "trashed"), true);
    try testing.expect((try tasks.prune(testing.allocator, &registry, repo)) == null);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    try testing.expectEqual(@as(usize, 1), (try tasks.list(arena.allocator(), &registry, repo)).len);
    try sh(&registry, repo, &.{ "rev-parse", "--verify", "--quiet", "fix-2" });

    const odd = (try tasks.deleteBranch(testing.allocator, &registry, repo, "-x")).?;
    defer testing.allocator.free(odd);
    try testing.expect((try tasks.deleteBranch(testing.allocator, &registry, repo, "fix-2")) == null);
    var gone = try sc.git.run(testing.allocator, &registry, repo, &.{ "rev-parse", "--verify", "--quiet", "fix-2" }, .{});
    defer gone.deinit(testing.allocator);
    try testing.expect(!gone.ok());
}

test "a worktree outside the authorized folders is refused" {
    var dir = try TestDir.init();
    defer dir.deinit();
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    try testing.expectError(error.NotAuthorized, tasks.create(testing.allocator, &registry, dir.path(), "/tmp/elsewhere/x", "x", "main"));
}
