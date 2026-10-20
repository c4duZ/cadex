//! What the panel does to the repository (docs/spec/source-control.md).
//! Each returns null on success or git's message (owned) on failure; the
//! app asks for confirmation before the destructive ones.

const std = @import("std");
const workspace = @import("../workspace/workspace.zig");
const git = @import("git.zig");
const language = @import("../../shared/language.zig");

const Registry = workspace.Registry;

/// git's first line of error, owned; null when it worked.
fn outcome(gpa: std.mem.Allocator, r: *git.Result) !?[]u8 {
    defer r.deinit(gpa);
    if (r.ok()) return null;
    return try gpa.dupe(u8, git.message(r.*));
}

fn runPaths(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8, head: []const []const u8, paths: []const []const u8) !?[]u8 {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(gpa);
    try args.appendSlice(gpa, head);
    try args.append(gpa, "--");
    try args.appendSlice(gpa, paths);
    var r = try git.run(gpa, registry, repo, args.items, .{});
    return outcome(gpa, &r);
}

pub fn stage(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8, paths: []const []const u8) !?[]u8 {
    return runPaths(gpa, registry, repo, &.{ "add", "--all" }, paths);
}

/// Before the first commit there is no HEAD to restore from: the paths
/// leave the index instead.
pub fn unstage(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8, paths: []const []const u8) !?[]u8 {
    if (!try hasHead(gpa, registry, repo)) return runPaths(gpa, registry, repo, &.{ "rm", "--cached", "-r", "--quiet" }, paths);
    return runPaths(gpa, registry, repo, &.{ "restore", "--staged" }, paths);
}

/// Throws away the work-tree changes of tracked paths (untracked ones go
/// to the Trash, which is the app's).
pub fn discard(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8, paths: []const []const u8) !?[]u8 {
    return runPaths(gpa, registry, repo, &.{"restore"}, paths);
}

/// Commits what is staged, or everything tracked with `all`.
pub fn commit(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8, message: []const u8, all: bool) !?[]u8 {
    if (std.mem.trim(u8, message, " \n\t").len == 0) return try gpa.dupe(u8, language.t("Write a commit message", "Escreva uma mensagem para o commit"));
    if (all) {
        if (try stage(gpa, registry, repo, &.{"."})) |err| return err;
    }
    var r = try git.run(gpa, registry, repo, &.{ "commit", "--quiet", "--file=-" }, .{ .stdin = message });
    return outcome(gpa, &r);
}

pub fn fetch(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8) !?[]u8 {
    var r = try git.run(gpa, registry, repo, &.{ "fetch", "--prune", "--quiet" }, .{ .timeout_ms = git.network_timeout_ms });
    return outcome(gpa, &r);
}

/// Only fast-forward: diverged branches are the user's to merge or rebase.
pub fn pull(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8) !?[]u8 {
    var r = try git.run(gpa, registry, repo, &.{ "pull", "--ff-only", "--quiet" }, .{ .timeout_ms = git.network_timeout_ms });
    defer r.deinit(gpa);
    if (r.ok()) return null;
    const text = git.message(r);
    if (std.mem.indexOf(u8, r.stderr, "Not possible to fast-forward") != null or std.mem.indexOf(u8, r.stderr, "diverg") != null) {
        return try gpa.dupe(u8, language.t("The branches have diverged: merge or rebase in the terminal", "As branches divergiram: faça merge ou rebase no terminal"));
    }
    return try gpa.dupe(u8, text);
}

/// Never forces. `publish`: the branch has no upstream yet (push -u origin).
pub fn push(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8, publish: ?[]const u8) !?[]u8 {
    var r = if (publish) |branch|
        try git.run(gpa, registry, repo, &.{ "push", "--quiet", "--set-upstream", "origin", branch }, .{ .timeout_ms = git.network_timeout_ms })
    else
        try git.run(gpa, registry, repo, &.{ "push", "--quiet" }, .{ .timeout_ms = git.network_timeout_ms });
    return outcome(gpa, &r);
}

/// Switches to `name`; a remote branch (origin/x) becomes a local one
/// tracking it.
pub fn switchTo(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8, name: []const u8, remote: bool) !?[]u8 {
    var r = if (remote) blk: {
        const local = if (std.mem.indexOfScalar(u8, name, '/')) |slash| name[slash + 1 ..] else name;
        break :blk try git.run(gpa, registry, repo, &.{ "switch", "--quiet", "--create", local, "--track", name }, .{});
    } else try git.run(gpa, registry, repo, &.{ "switch", "--quiet", name }, .{});
    return outcome(gpa, &r);
}

pub fn initRepository(gpa: std.mem.Allocator, registry: *Registry, folder: []const u8) !?[]u8 {
    var r = try git.run(gpa, registry, folder, &.{ "init", "--quiet" }, .{});
    return outcome(gpa, &r);
}

fn hasHead(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8) !bool {
    var r = try git.run(gpa, registry, repo, &.{ "rev-parse", "--verify", "--quiet", "HEAD" }, .{});
    defer r.deinit(gpa);
    return r.ok();
}

/// Local branches and remote ones without a local branch of the same name:
/// "local\tname" / "remote\tname" lines, the current branch first.
pub fn branches(gpa: std.mem.Allocator, registry: *Registry, repo: []const u8) ![]u8 {
    var r = try git.run(gpa, registry, repo, &.{ "for-each-ref", "--sort=-committerdate", "--format=%(HEAD)%09%(refname)", "refs/heads", "refs/remotes" }, .{});
    defer r.deinit(gpa);
    if (!r.ok()) return error.GitFailed;
    var locals: std.StringHashMapUnmanaged(void) = .empty;
    defer locals.deinit(gpa);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var current: []const u8 = "";
    var lines = std.mem.splitScalar(u8, r.stdout, '\n');
    while (lines.next()) |line| {
        const tab = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
        const ref = line[tab + 1 ..];
        if (std.mem.startsWith(u8, ref, "refs/heads/")) {
            const name = ref[11..];
            try locals.put(gpa, name, {});
            if (line[0] == '*') current = name;
        }
    }
    if (current.len > 0) try out.print(gpa, "local\t{s}\n", .{current});
    lines = std.mem.splitScalar(u8, r.stdout, '\n');
    while (lines.next()) |line| {
        const tab = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
        const ref = line[tab + 1 ..];
        if (std.mem.startsWith(u8, ref, "refs/heads/")) {
            if (line[0] != '*') try out.print(gpa, "local\t{s}\n", .{ref[11..]});
        } else if (std.mem.startsWith(u8, ref, "refs/remotes/")) {
            const name = ref[13..];
            if (std.mem.endsWith(u8, name, "/HEAD")) continue;
            const short = if (std.mem.indexOfScalar(u8, name, '/')) |slash| name[slash + 1 ..] else name;
            if (!locals.contains(short)) try out.print(gpa, "remote\t{s}\n", .{name});
        }
    }
    return out.toOwnedSlice(gpa);
}
