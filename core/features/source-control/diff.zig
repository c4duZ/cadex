//! The two sides of a file's diff and its patch (docs/spec/source-control.md):
//! staged compares HEAD with the index; not staged compares the index with
//! the disk. The app lays the sides out with the editor's colors.

const std = @import("std");
const workspace = @import("../workspace/workspace.zig");
const git = @import("git.zig");

/// Above this, no diff (the app offers to open the file).
pub const max_side_bytes = 2 * 1024 * 1024;

pub const Sides = struct {
    before: []u8,
    after: []u8,
    patch: []u8,
    binary: bool,
    too_large: bool,

    pub fn deinit(self: *Sides, gpa: std.mem.Allocator) void {
        gpa.free(self.before);
        gpa.free(self.after);
        gpa.free(self.patch);
    }
};

/// `path` relative to the repository; `orig` the old name of a rename.
pub fn sides(gpa: std.mem.Allocator, registry: *workspace.Registry, repo: []const u8, path: []const u8, orig: []const u8, staged: bool) !Sides {
    const old_path = if (orig.len > 0) orig else path;
    const before = try show(gpa, registry, repo, if (staged) "HEAD" else "", old_path);
    errdefer gpa.free(before);
    const after = if (staged) try show(gpa, registry, repo, "", path) else try readDisk(gpa, registry, repo, path);
    errdefer gpa.free(after);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(gpa);
    try args.appendSlice(gpa, &.{ "diff", "--no-color", "--no-ext-diff" });
    if (staged) try args.append(gpa, "--cached");
    try args.append(gpa, "--");
    if (orig.len > 0) try args.append(gpa, orig);
    try args.append(gpa, path);
    var r = try git.run(gpa, registry, repo, args.items, .{});
    errdefer r.deinit(gpa);
    gpa.free(r.stderr);
    r.stderr = &.{};
    const binary = isBinary(before) or isBinary(after);
    const too_large = before.len > max_side_bytes or after.len > max_side_bytes;
    return .{ .before = before, .after = after, .patch = r.stdout, .binary = binary, .too_large = too_large };
}

/// A file as a commit changed it (git-history): its first parent's version
/// and the commit's (nothing before a root commit), and the patch.
pub fn commitSides(gpa: std.mem.Allocator, registry: *workspace.Registry, repo: []const u8, sha: []const u8, path: []const u8, orig: []const u8) !Sides {
    for (sha) |ch| if (!std.ascii.isHex(ch)) return error.InvalidPattern;
    const parent_spec = try std.fmt.allocPrint(gpa, "{s}^1", .{sha});
    defer gpa.free(parent_spec);
    var parent = try git.run(gpa, registry, repo, &.{ "rev-parse", "--verify", "--quiet", parent_spec }, .{});
    defer parent.deinit(gpa);
    const base: ?[]const u8 = if (parent.ok()) std.mem.trimEnd(u8, parent.stdout, "\n") else null;
    const before = if (base) |b| try show(gpa, registry, repo, b, if (orig.len > 0) orig else path) else try gpa.alloc(u8, 0);
    errdefer gpa.free(before);
    const after = try show(gpa, registry, repo, sha, path);
    errdefer gpa.free(after);
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(gpa);
    try args.appendSlice(gpa, &.{ "diff-tree", "-p", "-M", "--no-color", "--no-ext-diff" });
    if (base) |b| try args.append(gpa, b) else try args.appendSlice(gpa, &.{ "--root", "--no-commit-id" });
    try args.appendSlice(gpa, &.{ sha, "--" });
    if (orig.len > 0) try args.append(gpa, orig);
    try args.append(gpa, path);
    var r = try git.run(gpa, registry, repo, args.items, .{});
    errdefer r.deinit(gpa);
    gpa.free(r.stderr);
    r.stderr = &.{};
    const binary = isBinary(before) or isBinary(after);
    const too_large = before.len > max_side_bytes or after.len > max_side_bytes;
    return .{ .before = before, .after = after, .patch = r.stdout, .binary = binary, .too_large = too_large };
}

/// `git show <rev>:<path>` (rev "" is the index); empty when the path is
/// not there (a new file).
fn show(gpa: std.mem.Allocator, registry: *workspace.Registry, repo: []const u8, rev: []const u8, path: []const u8) ![]u8 {
    const spec = try std.fmt.allocPrint(gpa, "{s}:{s}", .{ rev, path });
    defer gpa.free(spec);
    var r = try git.run(gpa, registry, repo, &.{ "show", spec }, .{});
    defer gpa.free(r.stderr);
    if (!r.ok()) {
        gpa.free(r.stdout);
        return gpa.alloc(u8, 0);
    }
    return r.stdout;
}

fn readDisk(gpa: std.mem.Allocator, registry: *workspace.Registry, repo: []const u8, path: []const u8) ![]u8 {
    var buf: workspace.paths.Buffer = undefined;
    const full = try std.fmt.bufPrint(&buf, "{s}/{s}", .{ repo, path });
    var real_buf: workspace.paths.Buffer = undefined;
    const real = registry.resolve(full, &real_buf) catch return gpa.alloc(u8, 0);
    var z: workspace.paths.Buffer = undefined;
    const fd = std.c.open((try workspace.paths.terminate(real, &z)).ptr, .{ .ACCMODE = .RDONLY, .CLOEXEC = true });
    if (fd < 0) return gpa.alloc(u8, 0);
    defer _ = std.c.close(fd);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var chunk: [64 * 1024]u8 = undefined;
    while (out.items.len <= max_side_bytes) {
        const n = std.c.read(fd, &chunk, chunk.len);
        if (n <= 0) break;
        try out.appendSlice(gpa, chunk[0..@intCast(n)]);
    }
    return out.toOwnedSlice(gpa);
}

fn isBinary(bytes: []const u8) bool {
    return std.mem.indexOfScalar(u8, bytes[0..@min(bytes.len, 8000)], 0) != null;
}
