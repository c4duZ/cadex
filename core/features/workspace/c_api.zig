//! The workspace feature's part of the C API (include/cadex.h).

const std = @import("std");
const status = @import("../../status.zig");
const workspace = @import("workspace.zig");
const terminal = @import("../terminal/terminal.zig");
const c_buffer = @import("../../shared/c_buffer.zig");
const handOut = c_buffer.handOut;
const clearOut = c_buffer.clearOut;

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

/// The WSL distributions installed, one per line ("Ubuntu\nDebian"), not
/// NUL-terminated; free with cadex_free. None (or not Windows): *out NULL.
pub export fn cadex_workspace_wsl_distros(out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    clearOut(out, out_len);
    const gpa = std.heap.c_allocator;
    const list = workspace.wsl.distros(gpa) catch return status.out_of_memory;
    defer {
        for (list) |d| gpa.free(d);
        gpa.free(list);
    }
    if (list.len == 0) return status.ok;
    const joined = std.mem.join(gpa, "\n", list) catch return status.out_of_memory;
    defer gpa.free(joined);
    return handOut(joined, out, out_len);
}

/// A path between Windows and a WSL distro: to_linux turns C:\x into
/// /mnt/c/x (and \\wsl.localhost\<d>\y into /y); otherwise /mnt/c/x into
/// C:\x and /y into \\wsl.localhost\<distro>\y. Free with cadex_free. A
/// path with no counterpart: CADEX_NOT_FOUND.
pub export fn cadex_workspace_wsl_path(distro: ?[*:0]const u8, path: ?[*:0]const u8, to_linux: bool, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    clearOut(out, out_len);
    const p = std.mem.span(path orelse return status.invalid_argument);
    var buf: [4096]u8 = undefined;
    const converted = if (to_linux)
        workspace.wsl.toLinux(p, &buf)
    else
        workspace.wsl.toWindows(std.mem.span(distro orelse return status.invalid_argument), p, &buf);
    return handOut(converted orelse return status.not_found, out, out_len);
}
