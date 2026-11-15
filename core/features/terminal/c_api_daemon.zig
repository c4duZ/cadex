//! The C API of the terminal daemon (include/cadex.h, plan 19 phase E2):
//! starting it when terminal.keepSessions is on, and ending the sessions no
//! pane took back after a launch. Mac only; the sessions themselves open
//! through cadex_terminal_open (c_api.zig).

const std = @import("std");
const status = @import("../../status.zig");
const client = @import("daemon_client.zig");

const gpa = std.heap.c_allocator;

/// Makes sure a daemon answers on `socket`, starting `helper` (the
/// cadex-terminald program) when none does; `scrollback` (or NULL) is where
/// it saves the sessions' output when the Mac shuts down.
pub export fn cadex_terminal_daemon_ensure(helper: ?[*:0]const u8, socket: ?[*:0]const u8, scrollback: ?[*:0]const u8) callconv(.c) status.Code {
    const h = helper orelse return status.invalid_argument;
    const s = socket orelse return status.invalid_argument;
    client.ensure(h, s, scrollback) catch |err| return switch (err) {
        error.SpawnFailed => status.spawn_failed,
        else => status.io_failed,
    };
    return status.ok;
}

/// Ends the daemon's sessions named with `prefix` that are not among the
/// `count` names in `claimed` and no app holds; `closed` gets how many.
pub export fn cadex_terminal_daemon_close_unclaimed(socket: ?[*:0]const u8, prefix: ?[*:0]const u8,
    claimed: ?[*]const [*:0]const u8, count: u32, closed: ?*u32) callconv(.c) status.Code {
    const s = socket orelse return status.invalid_argument;
    const p = prefix orelse return status.invalid_argument;
    if (count > 0 and claimed == null) return status.invalid_argument;
    const names = gpa.alloc([]const u8, count) catch return status.out_of_memory;
    defer gpa.free(names);
    for (names, 0..) |*name, i| name.* = std.mem.span(claimed.?[i]);
    const n = client.closeUnclaimed(gpa, std.mem.span(s), std.mem.span(p), names) catch return status.io_failed;
    if (closed) |out| out.* = @intCast(n);
    return status.ok;
}
