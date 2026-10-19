//! Sleeping and a monotonic clock in milliseconds without std.Io (Zig 0.16
//! moved std.time and std.Thread.sleep there): libc on the Mac, kernel32 on
//! Windows. Used by the terminal, search, explorer, Markdown and the
//! process runner's timeout.

const std = @import("std");
const builtin = @import("builtin");
const win32 = @import("win32.zig");

extern "c" fn usleep(microseconds: c_uint) c_int;

pub fn sleepMs(ms: u32) void {
    if (builtin.os.tag == .windows) win32.Sleep(ms) else _ = usleep(ms * 1000);
}

/// Milliseconds since an arbitrary start; only differences mean anything.
pub fn monotonicMs() i64 {
    if (builtin.os.tag == .windows) return @intCast(win32.GetTickCount64());
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(i64, ts.sec) * 1000 + @divTrunc(@as(i64, ts.nsec), 1_000_000);
}

test "the clock moves forward across a sleep" {
    const start = monotonicMs();
    sleepMs(30);
    try std.testing.expect(monotonicMs() - start >= 25);
}
