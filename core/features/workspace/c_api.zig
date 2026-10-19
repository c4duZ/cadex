//! The workspace feature's part of the C API (include/cadex.h).

const std = @import("std");
const status = @import("../../status.zig");
const workspace = @import("workspace.zig");
const terminal = @import("../terminal/terminal.zig");

/// Buffers handed to the app come from malloc, freed with cadex_free.
const gpa = std.heap.c_allocator;

/// Copies `text` into a malloc'd buffer for the app. A null `out` skips it.
fn handOut(text: []const u8, out: ?*?[*]u8, out_len: ?*usize) status.Code {
    const ptr = out orelse return status.ok;
    const copy = gpa.dupe(u8, text) catch return status.out_of_memory;
    ptr.* = copy.ptr;
    if (out_len) |len| len.* = copy.len;
    return status.ok;
}

fn clearOut(out: ?*?[*]u8, out_len: ?*usize) void {
    if (out) |ptr| ptr.* = null;
    if (out_len) |len| len.* = 0;
}

/// Authorizes an existing directory for this run. *out (optional) receives
/// its canonical path, not NUL-terminated; free with cadex_free.
pub export fn cadex_workspace_authorize(path: ?[*:0]const u8, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    clearOut(out, out_len);
    const p = std.mem.span(path orelse return status.invalid_argument);
    const real = workspace.registry().authorize(p) catch |err| return status.fromError(err);
    return handOut(real, out, out_len);
}

/// Whether `path` (absolute) resolves inside an authorized directory.
pub export fn cadex_workspace_is_authorized(path: ?[*:0]const u8) callconv(.c) bool {
    const p = std.mem.span(path orelse return false);
    return workspace.registry().allows(p);
}

/// Authorizes the current directory of a terminal session and returns it
/// like cadex_workspace_authorize. Unknown directory: CADEX_NOT_FOUND.
pub export fn cadex_workspace_authorize_terminal(session: ?*terminal.Session, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    clearOut(out, out_len);
    const s = session orelse return status.invalid_argument;
    var buffers: terminal.view.DirectoryBuffers = undefined;
    const dir = terminal.view.directory(s, &buffers) orelse return status.not_found;
    if (dir.len == 0) return status.not_found;
    const real = workspace.registry().authorize(dir) catch |err| return status.fromError(err);
    return handOut(real, out, out_len);
}

/// The folder the app was opened with: the first of argv[1...] naming an
/// existing directory (relative to `cwd`), canonical. None: *out is NULL.
/// It is not authorized: the app authorizes it when it opens it.
pub export fn cadex_workspace_launch_directory(
    argv: ?[*]const ?[*:0]const u8,
    argc: usize,
    cwd: ?[*:0]const u8,
    out: ?*?[*]u8,
    out_len: ?*usize,
) callconv(.c) status.Code {
    clearOut(out, out_len);
    const list = argv orelse return status.invalid_argument;
    const base = std.mem.span(cwd orelse return status.invalid_argument);
    var args: [64][]const u8 = undefined;
    const count = @min(argc, args.len);
    for (args[0..count], 0..) |*arg, i| arg.* = std.mem.span(list[i] orelse return status.invalid_argument);
    var buf: workspace.paths.Buffer = undefined;
    const dir = workspace.launchDirectory(args[0..count], base, &buf) orelse return status.ok;
    return handOut(dir, out, out_len);
}

const testing = std.testing;

test "authorizes through the C API and refuses outside" {
    var out: ?[*]u8 = null;
    var len: usize = 0;
    try testing.expectEqual(status.ok, cadex_workspace_authorize("/usr/bin", &out, &len));
    defer std.c.free(out);
    try testing.expectEqualStrings("/usr/bin", out.?[0..len]);
    try testing.expect(cadex_workspace_is_authorized("/usr/bin/env"));
    try testing.expect(!cadex_workspace_is_authorized("/usr/bin/../lib"));
    try testing.expectEqual(status.not_found, cadex_workspace_authorize("/no/such/dir", null, null));
    try testing.expectEqual(status.invalid_argument, cadex_workspace_authorize("relative", null, null));
}

test "finds the launch directory in argv" {
    const argv = [_]?[*:0]const u8{ "Cadex", "-psn_0_1", "bin" };
    var out: ?[*]u8 = null;
    var len: usize = 0;
    try testing.expectEqual(status.ok, cadex_workspace_launch_directory(&argv, argv.len, "/usr", &out, &len));
    defer std.c.free(out);
    try testing.expectEqualStrings("/usr/bin", out.?[0..len]);
}
