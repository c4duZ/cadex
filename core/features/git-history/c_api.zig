//! The git-history feature's part of the C API (include/cadex.h).

const std = @import("std");
const status = @import("../../status.zig");
const workspace = @import("../workspace/workspace.zig");
const c_buffer = @import("../../shared/c_buffer.zig");
const history = @import("history.zig");

const Log = history.log.Log;
const gpa = std.heap.c_allocator;

fn span(p: ?[*:0]const u8) ?[]const u8 {
    return std.mem.span(p orelse return null);
}

/// query "" (or NULL): every commit with the graph; otherwise the commits
/// whose subject, author or sha match, without a graph.
pub export fn cadex_history_open(repo: ?[*:0]const u8, query: ?[*:0]const u8, current_only: bool, out: ?*?*Log) callconv(.c) status.Code {
    const result = out orelse return status.invalid_argument;
    result.* = null;
    const r = span(repo) orelse return status.invalid_argument;
    const log = gpa.create(Log) catch return status.out_of_memory;
    log.* = Log.init(gpa, workspace.registry(), r, span(query) orelse "", current_only) catch |err| {
        gpa.destroy(log);
        return status.fromError(err);
    };
    result.* = log;
    return status.ok;
}

pub export fn cadex_history_next(log: ?*Log, count: usize, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    c_buffer.clearOut(out, out_len);
    const l = log orelse return status.invalid_argument;
    const text = l.next(count) catch |err| return status.fromError(err);
    defer gpa.free(text);
    return c_buffer.handOut(text, out, out_len);
}

pub export fn cadex_history_close(log: ?*Log) callconv(.c) void {
    const l = log orelse return;
    l.deinit();
    gpa.destroy(l);
}

pub export fn cadex_history_details(repo: ?[*:0]const u8, sha: ?[*:0]const u8, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    c_buffer.clearOut(out, out_len);
    const r = span(repo) orelse return status.invalid_argument;
    const s = span(sha) orelse return status.invalid_argument;
    const text = history.details.read(gpa, workspace.registry(), r, s) catch |err| return status.fromError(err);
    defer gpa.free(text);
    return c_buffer.handOut(text, out, out_len);
}

/// CADEX_NOT_FOUND: no origin, or one that is not a web host.
pub export fn cadex_history_remote_url(repo: ?[*:0]const u8, sha: ?[*:0]const u8, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    c_buffer.clearOut(out, out_len);
    const r = span(repo) orelse return status.invalid_argument;
    const s = span(sha) orelse return status.invalid_argument;
    if (!history.details.isSha(s)) return status.invalid_argument;
    const url = (history.remote.originCommitUrl(gpa, workspace.registry(), r, s) catch |err| return status.fromError(err)) orelse return status.not_found;
    defer gpa.free(url);
    return c_buffer.handOut(url, out, out_len);
}
