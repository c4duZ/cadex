//! A task's worktree through the user's `git` (docs/spec/worktrees.md):
//! the branch a task's name becomes, the repository's worktrees, making one
//! and taking one away only when nothing would be lost. Runs through
//! source-control's runner: only in authorized folders, with a time limit.

const std = @import("std");
const workspace = @import("../workspace/workspace.zig");
const sc = @import("../source-control/source_control.zig");
const git = sc.git;

/// "Corrigir login!" -> "corrigir-login": lowercase ASCII letters and
/// digits, the rest as one "-", at most 60; "task" when nothing is left.
/// Accented letters lose their accent (á -> a). Caller frees.
pub fn branchName(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const view = std.unicode.Utf8View.init(name) catch std.unicode.Utf8View.initUnchecked("");
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| {
        const c = plain(cp);
        if (c != 0) {
            try out.append(gpa, c);
        } else if (out.items.len > 0 and out.items[out.items.len - 1] != '-') {
            try out.append(gpa, '-');
        }
        if (out.items.len >= 60) break;
    }
    while (out.items.len > 0 and out.items[out.items.len - 1] == '-') _ = out.pop();
    if (out.items.len == 0) try out.appendSlice(gpa, "task");
    return out.toOwnedSlice(gpa);
}

/// A letter or digit as plain lowercase ASCII, or 0.
fn plain(cp: u21) u8 {
    if (cp < 128) {
        const c: u8 = @intCast(cp);
        if (std.ascii.isAlphanumeric(c)) return std.ascii.toLower(c);
        return 0;
    }
    return switch (cp) {
        'á', 'à', 'â', 'ã', 'ä', 'Á', 'À', 'Â', 'Ã', 'Ä' => 'a',
        'é', 'è', 'ê', 'ë', 'É', 'È', 'Ê', 'Ë' => 'e',
        'í', 'ì', 'î', 'ï', 'Í', 'Ì', 'Î', 'Ï' => 'i',
        'ó', 'ò', 'ô', 'õ', 'ö', 'Ó', 'Ò', 'Ô', 'Õ', 'Ö' => 'o',
        'ú', 'ù', 'û', 'ü', 'Ú', 'Ù', 'Û', 'Ü' => 'u',
        'ç', 'Ç' => 'c',
        'ñ', 'Ñ' => 'n',
        else => 0,
    };
}

pub const Worktree = struct {
    path: []const u8,
    /// Empty when detached.
    branch: []const u8,
    head: []const u8,
};

/// The repository's worktrees, the main one first (`git worktree list
/// --porcelain`). Strings live in `arena`.
pub fn list(arena: std.mem.Allocator, registry: *workspace.Registry, repo: []const u8) ![]Worktree {
    var r = try git.run(arena, registry, repo, &.{ "worktree", "list", "--porcelain" }, .{});
    defer r.deinit(arena);
    if (!r.ok()) return error.GitFailed;
    var out: std.ArrayList(Worktree) = .empty;
    var current: ?Worktree = null;
    var lines = std.mem.splitScalar(u8, r.stdout, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "worktree ")) {
            if (current) |w| try out.append(arena, w);
            current = .{ .path = try arena.dupe(u8, line["worktree ".len..]), .branch = "", .head = "" };
        } else if (current != null and std.mem.startsWith(u8, line, "HEAD ")) {
            current.?.head = try arena.dupe(u8, line["HEAD ".len..]);
        } else if (current != null and std.mem.startsWith(u8, line, "branch refs/heads/")) {
            current.?.branch = try arena.dupe(u8, line["branch refs/heads/".len..]);
        }
    }
    if (current) |w| try out.append(arena, w);
    return out.toOwnedSlice(arena);
}

/// A new branch `branch` from `base` in a new worktree at `path`, whose
/// parent folder must be authorized (the app asks the owner once). Returns
/// git's message when it refused, else null. Caller frees the message.
pub fn create(gpa: std.mem.Allocator, registry: *workspace.Registry, repo: []const u8, path: []const u8, branch: []const u8, base: []const u8) !?[]u8 {
    const parent = std.fs.path.dirname(path) orelse return error.NotAuthorized;
    if (!registry.allows(parent)) return error.NotAuthorized;
    var r = try git.run(gpa, registry, repo, &.{ "worktree", "add", "-b", branch, path, base }, .{});
    defer r.deinit(gpa);
    if (r.ok()) return null;
    return try gpa.dupe(u8, git.message(r));
}

/// What would be lost by taking the worktree away: its changed files (git
/// status) and its commits on no other branch nor upstream. Empty: safe.
/// One finding per line. Caller frees.
pub fn whatWouldBeLost(gpa: std.mem.Allocator, registry: *workspace.Registry, path: []const u8, branch: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var s = try git.run(gpa, registry, path, &.{ "status", "--porcelain" }, .{});
    defer s.deinit(gpa);
    if (!s.ok()) return error.GitFailed;
    var lines = std.mem.splitScalar(u8, s.stdout, '\n');
    while (lines.next()) |line| {
        if (line.len < 4) continue;
        try out.appendSlice(gpa, line[3..]);
        try out.append(gpa, '\n');
    }
    // Commits only this branch has: not on any other local branch nor
    // remote (--exclude takes the branch's bare name before --branches).
    const exclude = try std.fmt.allocPrint(gpa, "--exclude={s}", .{if (branch.len > 0) branch else "HEAD"});
    defer gpa.free(exclude);
    var c = try git.run(gpa, registry, path, &.{ "log", "--oneline", "HEAD", "--not", exclude, "--branches", "--remotes", "--" }, .{});
    defer c.deinit(gpa);
    if (c.ok()) {
        var commits = std.mem.splitScalar(u8, std.mem.trimEnd(u8, c.stdout, "\n"), '\n');
        while (commits.next()) |line| {
            if (line.len == 0) continue;
            try out.appendSlice(gpa, "commit ");
            try out.appendSlice(gpa, line);
            try out.append(gpa, '\n');
        }
    }
    return out.toOwnedSlice(gpa);
}

/// Takes the worktree away (`git worktree remove`, which itself refuses a
/// worktree with changes) and, when asked, its branch with `git branch -d`,
/// which refuses one not merged. Returns git's message when it refused.
pub fn remove(gpa: std.mem.Allocator, registry: *workspace.Registry, repo: []const u8, path: []const u8, branch: ?[]const u8) !?[]u8 {
    var r = try git.run(gpa, registry, repo, &.{ "worktree", "remove", path }, .{});
    defer r.deinit(gpa);
    if (!r.ok()) return try gpa.dupe(u8, git.message(r));
    if (branch) |b| {
        var d = try git.run(gpa, registry, repo, &.{ "branch", "-d", b }, .{});
        defer d.deinit(gpa);
        if (!d.ok()) return try gpa.dupe(u8, git.message(d));
    }
    return null;
}
