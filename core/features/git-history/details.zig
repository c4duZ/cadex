//! A commit's details (docs/spec/git-history.md): the whole message and
//! the files it changed, with the kind of change and the lines added and
//! removed. A merge is compared with its first parent, like `git show
//! --first-parent`; a root commit with nothing.

const std = @import("std");
const sc = @import("../source-control/source_control.zig");
const workspace = @import("../workspace/workspace.zig");

/// Only a hex id reaches git's arguments: never an option.
pub fn isSha(text: []const u8) bool {
    if (text.len < 4 or text.len > 64) return false;
    for (text) |ch| if (!std.ascii.isHex(ch)) return false;
    return true;
}

/// "parents \x1e message \x1e" then a line per file:
/// letter \t added \t removed \t path \t old path (added and removed are
/// "-" for a binary file). Caller frees.
pub fn read(gpa: std.mem.Allocator, registry: *workspace.Registry, repo: []const u8, sha: []const u8) ![]u8 {
    if (!isSha(sha)) return error.InvalidPattern;
    var head = try sc.git.run(gpa, registry, repo, &.{ "log", "-1", "--format=%P%x1e%B%x1e", sha, "--" }, .{});
    defer head.deinit(gpa);
    if (!head.ok()) return error.NotFound;
    const end = std.mem.lastIndexOfScalar(u8, head.stdout, 0x1e) orelse return error.GitFailed;
    const parents = head.stdout[0 .. std.mem.indexOfScalar(u8, head.stdout, 0x1e) orelse 0];
    var first = std.mem.tokenizeScalar(u8, parents, ' ');
    const base = first.next();

    var names = try diffTree(gpa, registry, repo, base, sha, "--name-status");
    defer names.deinit(gpa);
    var counts = try diffTree(gpa, registry, repo, base, sha, "--numstat");
    defer counts.deinit(gpa);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, head.stdout[0 .. end + 1]);
    try files(&out, gpa, names.stdout, counts.stdout);
    return out.toOwnedSlice(gpa);
}

fn diffTree(gpa: std.mem.Allocator, registry: *workspace.Registry, repo: []const u8, base: ?[]const u8, sha: []const u8, kind: []const u8) !sc.git.Result {
    var r = if (base) |b|
        try sc.git.run(gpa, registry, repo, &.{ "diff-tree", "-r", "-z", "-M", "--no-color", kind, b, sha, "--" }, .{})
    else
        try sc.git.run(gpa, registry, repo, &.{ "diff-tree", "-r", "-z", "-M", "--no-color", "--root", "--no-commit-id", kind, sha, "--" }, .{});
    if (!r.ok()) {
        r.deinit(gpa);
        return error.GitFailed;
    }
    return r;
}

/// Zips the -z outputs of --name-status ("R100\0old\0new\0", "M\0path\0")
/// and --numstat ("1\t2\tpath\0", renames "1\t2\t\0old\0new\0"): the same
/// diff, so the same order.
pub fn files(out: *std.ArrayList(u8), gpa: std.mem.Allocator, names: []const u8, counts: []const u8) !void {
    var n = std.mem.splitScalar(u8, names, 0);
    var c = std.mem.splitScalar(u8, counts, 0);
    while (n.next()) |status| {
        if (status.len == 0) continue;
        const renamed = status[0] == 'R' or status[0] == 'C';
        const first = n.next() orelse break;
        const second = if (renamed) n.next() orelse break else "";
        const path = if (renamed) second else first;
        const orig = if (renamed) first else "";
        var added: []const u8 = "-";
        var removed: []const u8 = "-";
        if (c.next()) |count| {
            var f = std.mem.splitScalar(u8, count, '\t');
            added = f.next() orelse "-";
            removed = f.next() orelse "-";
            // A rename's numstat names the paths in the next two fields.
            if (std.mem.endsWith(u8, count, "\t")) {
                _ = c.next();
                _ = c.next();
            }
        }
        try out.print(gpa, "{c}\t{s}\t{s}\t{s}\t{s}\n", .{ status[0], added, removed, path, orig });
    }
}

test "name-status and numstat zip into one line per file" {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(std.testing.allocator);
    try files(&out, std.testing.allocator, "M\x00a.zig\x00R090\x00velho.txt\x00novo nome.txt\x00A\x00img.png\x00", "3\t1\ta.zig\x002\t0\t\x00velho.txt\x00novo nome.txt\x00-\t-\timg.png\x00");
    try std.testing.expectEqualStrings("M\t3\t1\ta.zig\t\nR\t2\t0\tnovo nome.txt\tvelho.txt\nA\t-\t-\timg.png\t\n", out.items);
}

test "only hex ids are commits" {
    try std.testing.expect(isSha("a1b2c3d"));
    try std.testing.expect(!isSha("--output=x"));
    try std.testing.expect(!isSha("abc"));
}
