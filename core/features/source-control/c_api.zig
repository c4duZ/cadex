//! The source-control feature's part of the C API (include/cadex.h).
//! Listings are lines of tab-separated fields; a failed action returns
//! CADEX_IO_FAILED with git's message in *message.

const std = @import("std");
const status_code = @import("../../status.zig");
const workspace = @import("../workspace/workspace.zig");
const c_buffer = @import("../../shared/c_buffer.zig");
const sc = @import("source_control.zig");

const Code = status_code.Code;
const gpa = std.heap.c_allocator;

fn span(p: ?[*:0]const u8) ?[]const u8 {
    return std.mem.span(p orelse return null);
}

pub export fn cadex_git_available() callconv(.c) bool {
    return sc.git.available(gpa);
}

/// The repository's top folder. CADEX_NOT_FOUND: not in a repository.
pub export fn cadex_git_root(folder: ?[*:0]const u8, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) Code {
    c_buffer.clearOut(out, out_len);
    const f = span(folder) orelse return status_code.invalid_argument;
    const top = (sc.git.root(gpa, workspace.registry(), f) catch |err| return status_code.fromError(err)) orelse return status_code.not_found;
    defer gpa.free(top);
    return c_buffer.handOut(top, out, out_len);
}

/// "branch \t oid \t upstream \t ahead \t behind", then per changed path
/// "kind \t X \t Y \t path \t orig" (kind 0 changed, 1 renamed, 2 conflict,
/// 3 untracked; X the index letter, Y the work tree's).
pub export fn cadex_git_status(repo: ?[*:0]const u8, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) Code {
    c_buffer.clearOut(out, out_len);
    const r = span(repo) orelse return status_code.invalid_argument;
    var s = sc.status.read(gpa, workspace.registry(), r) catch |err| return status_code.fromError(err);
    defer s.deinit();
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    text.print(gpa, "{s}\t{s}\t{s}\t{d}\t{d}\n", .{ s.branch, s.oid, s.upstream, s.ahead, s.behind }) catch return status_code.out_of_memory;
    for (s.entries) |e| {
        text.print(gpa, "{d}\t{c}\t{c}\t{s}\t{s}\n", .{ @intFromEnum(e.kind), e.index, e.worktree, e.path, e.orig }) catch return status_code.out_of_memory;
    }
    return c_buffer.handOut(text.items, out, out_len);
}

fn paths(list: ?[*]const ?[*:0]const u8, count: usize, buf: [][]const u8) ?[]const []const u8 {
    if (count > buf.len) return null;
    const l = list orelse return null;
    for (buf[0..count], 0..) |*p, i| p.* = std.mem.span(l[i] orelse return null);
    return buf[0..count];
}

/// Turns an action's outcome into a status and the message.
fn finish(result: anyerror!?[]u8, message: ?*?[*]u8, message_len: ?*usize) Code {
    c_buffer.clearOut(message, message_len);
    const err_text = result catch |err| return status_code.fromError(err);
    const text = err_text orelse return status_code.ok;
    defer gpa.free(text);
    _ = c_buffer.handOut(text, message, message_len);
    return status_code.io_failed;
}

const PathAction = enum { stage, unstage, discard };

fn pathAction(action: PathAction, repo: ?[*:0]const u8, list: ?[*]const ?[*:0]const u8, count: usize, message: ?*?[*]u8, message_len: ?*usize) Code {
    const r = span(repo) orelse return status_code.invalid_argument;
    var buf: [4096][]const u8 = undefined;
    const p = paths(list, count, &buf) orelse return status_code.invalid_argument;
    const reg = workspace.registry();
    return finish(switch (action) {
        .stage => sc.actions.stage(gpa, reg, r, p),
        .unstage => sc.actions.unstage(gpa, reg, r, p),
        .discard => sc.actions.discard(gpa, reg, r, p),
    }, message, message_len);
}

pub export fn cadex_git_stage(repo: ?[*:0]const u8, list: ?[*]const ?[*:0]const u8, count: usize, message: ?*?[*]u8, message_len: ?*usize) callconv(.c) Code {
    return pathAction(.stage, repo, list, count, message, message_len);
}

pub export fn cadex_git_unstage(repo: ?[*:0]const u8, list: ?[*]const ?[*:0]const u8, count: usize, message: ?*?[*]u8, message_len: ?*usize) callconv(.c) Code {
    return pathAction(.unstage, repo, list, count, message, message_len);
}

pub export fn cadex_git_discard(repo: ?[*:0]const u8, list: ?[*]const ?[*:0]const u8, count: usize, message: ?*?[*]u8, message_len: ?*usize) callconv(.c) Code {
    return pathAction(.discard, repo, list, count, message, message_len);
}

pub export fn cadex_git_commit(repo: ?[*:0]const u8, text: ?[*:0]const u8, all: bool, message: ?*?[*]u8, message_len: ?*usize) callconv(.c) Code {
    const r = span(repo) orelse return status_code.invalid_argument;
    const t = span(text) orelse return status_code.invalid_argument;
    return finish(sc.actions.commit(gpa, workspace.registry(), r, t, all), message, message_len);
}

pub export fn cadex_git_fetch(repo: ?[*:0]const u8, message: ?*?[*]u8, message_len: ?*usize) callconv(.c) Code {
    const r = span(repo) orelse return status_code.invalid_argument;
    return finish(sc.actions.fetch(gpa, workspace.registry(), r), message, message_len);
}

pub export fn cadex_git_pull(repo: ?[*:0]const u8, message: ?*?[*]u8, message_len: ?*usize) callconv(.c) Code {
    const r = span(repo) orelse return status_code.invalid_argument;
    return finish(sc.actions.pull(gpa, workspace.registry(), r), message, message_len);
}

/// `publish`: a branch without upstream to push as origin/<branch>; NULL
/// pushes to the upstream.
pub export fn cadex_git_push(repo: ?[*:0]const u8, publish: ?[*:0]const u8, message: ?*?[*]u8, message_len: ?*usize) callconv(.c) Code {
    const r = span(repo) orelse return status_code.invalid_argument;
    return finish(sc.actions.push(gpa, workspace.registry(), r, span(publish)), message, message_len);
}

/// "local \t name" / "remote \t name" per line, the current branch first.
pub export fn cadex_git_branches(repo: ?[*:0]const u8, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) Code {
    c_buffer.clearOut(out, out_len);
    const r = span(repo) orelse return status_code.invalid_argument;
    const list = sc.actions.branches(gpa, workspace.registry(), r) catch |err| return status_code.fromError(err);
    defer gpa.free(list);
    return c_buffer.handOut(list, out, out_len);
}

pub export fn cadex_git_switch(repo: ?[*:0]const u8, name: ?[*:0]const u8, remote: bool, message: ?*?[*]u8, message_len: ?*usize) callconv(.c) Code {
    const r = span(repo) orelse return status_code.invalid_argument;
    const n = span(name) orelse return status_code.invalid_argument;
    return finish(sc.actions.switchTo(gpa, workspace.registry(), r, n, remote), message, message_len);
}

pub export fn cadex_git_init(folder: ?[*:0]const u8, message: ?*?[*]u8, message_len: ?*usize) callconv(.c) Code {
    const f = span(folder) orelse return status_code.invalid_argument;
    return finish(sc.actions.initRepository(gpa, workspace.registry(), f), message, message_len);
}

pub const Diff = extern struct {
    before: ?[*]u8,
    before_len: usize,
    after: ?[*]u8,
    after_len: usize,
    patch: ?[*]u8,
    patch_len: usize,
    binary: bool,
    too_large: bool,
};

pub export fn cadex_git_diff(repo: ?[*:0]const u8, path: ?[*:0]const u8, orig: ?[*:0]const u8, staged: bool, out: ?*Diff) callconv(.c) Code {
    const d = out orelse return status_code.invalid_argument;
    d.* = std.mem.zeroes(Diff);
    const r = span(repo) orelse return status_code.invalid_argument;
    const p = span(path) orelse return status_code.invalid_argument;
    var sides = sc.diff.sides(gpa, workspace.registry(), r, p, span(orig) orelse "", staged) catch |err| return status_code.fromError(err);
    defer sides.deinit(gpa);
    _ = c_buffer.handOut(sides.before, &d.before, &d.before_len);
    _ = c_buffer.handOut(sides.after, &d.after, &d.after_len);
    _ = c_buffer.handOut(sides.patch, &d.patch, &d.patch_len);
    d.binary = sides.binary;
    d.too_large = sides.too_large;
    return status_code.ok;
}

pub export fn cadex_git_diff_free(diff: ?*Diff) callconv(.c) void {
    const d = diff orelse return;
    std.c.free(d.before);
    std.c.free(d.after);
    std.c.free(d.patch);
    d.* = std.mem.zeroes(Diff);
}
