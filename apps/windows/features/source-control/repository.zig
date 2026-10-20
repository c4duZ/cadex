//! A thin layer over the core's source control (cadex_git_*, include/cadex.h).
//! Every call blocks until git ends: only jobs on the worker call these
//! (worker.zig), never the window's thread.

const std = @import("std");
const cadex = @import("cadex");

/// What an action said: nothing when it worked, git's message otherwise,
/// kept short and inline so a job owns it without another allocation.
pub const Message = struct {
    failed: bool = false,
    buf: [600]u8 = undefined,
    len: usize = 0,

    pub fn text(self: *const Message) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn set(self: *Message, value: []const u8) void {
        self.failed = true;
        // Git's first lines say what went wrong; the rest is advice.
        const trimmed = std.mem.trim(u8, value, " \r\n\t");
        self.len = @min(trimmed.len, self.buf.len);
        @memcpy(self.buf[0..self.len], trimmed[0..self.len]);
    }
};

pub fn available() bool {
    return cadex.cadex_git_available();
}

/// A C string copy of `value`, for the core.
pub fn z(gpa: std.mem.Allocator, value: []const u8) ![:0]u8 {
    return gpa.dupeZ(u8, value);
}

/// A listing of the core, copied into `gpa`; null when the call failed.
fn listing(gpa: std.mem.Allocator, code: cadex.cadex_status, out: [*c]u8, len: usize) ?[]u8 {
    defer cadex.cadex_free(out);
    if (code != cadex.CADEX_OK) return null;
    if (out == null) return gpa.dupe(u8, "") catch null;
    return gpa.dupe(u8, out[0..len]) catch null;
}

/// The repository's top folder holding `folder`, or null (none, or no git).
pub fn findRoot(gpa: std.mem.Allocator, folder: [:0]const u8) ?[]u8 {
    var out: [*c]u8 = null;
    var len: usize = 0;
    const s = cadex.cadex_git_root(folder.ptr, &out, &len);
    const top = listing(gpa, s, out, len) orelse return null;
    // rev-parse ends the line; the folder does not.
    const end = std.mem.trimEnd(u8, top, "\r\n").len;
    return gpa.realloc(top, end) catch top[0..end];
}

pub fn status(gpa: std.mem.Allocator, root: [:0]const u8) ?[]u8 {
    var out: [*c]u8 = null;
    var len: usize = 0;
    return listing(gpa, cadex.cadex_git_status(root.ptr, &out, &len), out, len);
}

/// "local \t name" / "remote \t name" per line, the current branch first.
pub fn branches(gpa: std.mem.Allocator, root: [:0]const u8) ?[]u8 {
    var out: [*c]u8 = null;
    var len: usize = 0;
    return listing(gpa, cadex.cadex_git_branches(root.ptr, &out, &len), out, len);
}

/// Turns an action's outcome into a Message.
fn outcome(s: cadex.cadex_status, out: [*c]u8, len: usize) Message {
    defer cadex.cadex_free(out);
    var m: Message = .{};
    if (s == cadex.CADEX_OK) return m;
    if (s == cadex.CADEX_GIT_MISSING) {
        m.set("O git não foi encontrado");
    } else if (s == cadex.CADEX_NOT_AUTHORIZED) {
        m.set("Esta pasta não está autorizada no workspace");
    } else if (out != null and len > 0) {
        m.set(out[0..len]);
    } else {
        m.set("O git falhou");
    }
    return m;
}

pub const PathAction = enum { stage, unstage, discard };

/// The core takes at most 4096 paths a call (core/features/source-control/c_api.zig).
const paths_per_call = 4000;

pub fn onPaths(action: PathAction, root: [:0]const u8, paths: []const [:0]const u8) Message {
    var start: usize = 0;
    while (start < paths.len) {
        const chunk = paths[start..@min(start + paths_per_call, paths.len)];
        start += chunk.len;
        var list: [paths_per_call][*c]const u8 = undefined;
        for (chunk, 0..) |p, i| list[i] = p.ptr;
        var out: [*c]u8 = null;
        var len: usize = 0;
        const s = switch (action) {
            .stage => cadex.cadex_git_stage(root.ptr, &list, chunk.len, &out, &len),
            .unstage => cadex.cadex_git_unstage(root.ptr, &list, chunk.len, &out, &len),
            .discard => cadex.cadex_git_discard(root.ptr, &list, chunk.len, &out, &len),
        };
        const m = outcome(s, out, len);
        if (m.failed) return m;
    }
    return .{};
}

pub fn commit(root: [:0]const u8, text: [:0]const u8, all: bool) Message {
    var out: [*c]u8 = null;
    var len: usize = 0;
    return outcome(cadex.cadex_git_commit(root.ptr, text.ptr, all, &out, &len), out, len);
}

pub const Sync = enum { fetch, pull };

pub fn sync(which: Sync, root: [:0]const u8) Message {
    var out: [*c]u8 = null;
    var len: usize = 0;
    const s = switch (which) {
        .fetch => cadex.cadex_git_fetch(root.ptr, &out, &len),
        .pull => cadex.cadex_git_pull(root.ptr, &out, &len),
    };
    return outcome(s, out, len);
}

/// publish: push this branch to origin and track it; null: the upstream.
pub fn push(root: [:0]const u8, publish: ?[:0]const u8) Message {
    var out: [*c]u8 = null;
    var len: usize = 0;
    const branch: [*c]const u8 = if (publish) |p| p.ptr else null;
    return outcome(cadex.cadex_git_push(root.ptr, branch, &out, &len), out, len);
}

pub fn switchTo(root: [:0]const u8, name: [:0]const u8, remote: bool) Message {
    var out: [*c]u8 = null;
    var len: usize = 0;
    return outcome(cadex.cadex_git_switch(root.ptr, name.ptr, remote, &out, &len), out, len);
}

pub fn initialize(folder: [:0]const u8) Message {
    var out: [*c]u8 = null;
    var len: usize = 0;
    return outcome(cadex.cadex_git_init(folder.ptr, &out, &len), out, len);
}

/// A file's two sides and its patch, gpa-owned.
pub const Diff = struct {
    before: []u8,
    after: []u8,
    patch: []u8,
    binary: bool,
    too_large: bool,

    pub fn deinit(self: *Diff, gpa: std.mem.Allocator) void {
        gpa.free(self.before);
        gpa.free(self.after);
        gpa.free(self.patch);
    }
};

/// The working copy's diff (staged: HEAD against the index), or, with
/// `commit`, the file as that commit changed it. null when it failed.
pub fn diff(gpa: std.mem.Allocator, root: [:0]const u8, path: [:0]const u8, orig: ?[:0]const u8, staged: bool, commit_sha: ?[:0]const u8) ?Diff {
    var d: cadex.cadex_git_diff_sides = std.mem.zeroes(cadex.cadex_git_diff_sides);
    const old: [*c]const u8 = if (orig) |o| o.ptr else null;
    const s = if (commit_sha) |sha|
        cadex.cadex_git_diff_commit(root.ptr, sha.ptr, path.ptr, old, &d)
    else
        cadex.cadex_git_diff(root.ptr, path.ptr, old, staged, &d);
    if (s != cadex.CADEX_OK) return null;
    defer cadex.cadex_git_diff_free(&d);
    const before = copy(gpa, d.before, d.before_len) orelse return null;
    const after = copy(gpa, d.after, d.after_len) orelse {
        gpa.free(before);
        return null;
    };
    const patch = copy(gpa, d.patch, d.patch_len) orelse {
        gpa.free(before);
        gpa.free(after);
        return null;
    };
    return .{ .before = before, .after = after, .patch = patch, .binary = d.binary, .too_large = d.too_large };
}

fn copy(gpa: std.mem.Allocator, p: [*c]u8, len: usize) ?[]u8 {
    if (p == null) return gpa.alloc(u8, 0) catch null;
    return gpa.dupe(u8, p[0..len]) catch null;
}

/// root + "/" + a path of git's, with Windows separators, for the app
/// (open, Recycle Bin, Explorer). Caller frees.
pub fn absolute(gpa: std.mem.Allocator, root: []const u8, relative: []const u8) ![]u8 {
    const joined = try std.mem.concat(gpa, u8, &.{ root, "/", relative });
    for (joined) |*ch| {
        if (ch.* == '/') ch.* = '\\';
    }
    return joined;
}

test "paths for the app use Windows separators" {
    const p = try absolute(std.testing.allocator, "C:/src/cadex", "apps/a b.zig");
    defer std.testing.allocator.free(p);
    try std.testing.expectEqualStrings("C:\\src\\cadex\\apps\\a b.zig", p);
}

test "a message keeps git's text, trimmed and bounded" {
    var m: Message = .{};
    m.set("  fatal: not a repository\n");
    try std.testing.expect(m.failed);
    try std.testing.expectEqualStrings("fatal: not a repository", m.text());
}

test {
    @import("win32").refAllDeep(@This());
}
