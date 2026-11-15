//! The `cadex` command line: the subcommand picks the work. Kept to libc
//! reads and writes so each call stays small; Claude Code runs the status
//! line after every message.

const std = @import("std");
const statusline = @import("statusline.zig");
const hook = @import("hook.zig");

const usage_text =
    \\usage: cadex statusline       (Claude Code's status line, from a session Cadex opened)
    \\       cadex hook <event>     (a Claude Code hook: tells the Cadex app, never waits)
    \\
;

pub fn main(init: std.process.Init.Minimal) u8 {
    var args = init.args.iterate();
    _ = args.next();
    const sub = args.next() orelse return fail(usage_text);
    if (std.mem.eql(u8, sub, "statusline")) return runStatusline();
    if (std.mem.eql(u8, sub, "hook")) return runHook(args.next() orelse return fail(usage_text));
    return fail(usage_text);
}

fn runHook(event: []const u8) u8 {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();
    const input = readStdin(gpa) catch return 0;
    defer gpa.free(input);
    const out = (hook.run(gpa, event, input) catch return 0) orelse return 0;
    defer gpa.free(out);
    writeAll(1, out);
    return 0;
}

fn runStatusline() u8 {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();
    const input = readStdin(gpa) catch return 0;
    defer gpa.free(input);
    const out = statusline.run(gpa, input, statusline.Env.fromProcess()) catch return 0;
    defer gpa.free(out);
    writeAll(1, out);
    return 0;
}

/// The JSON Claude Code sends; a few KB, capped at 1 MB so a runaway pipe
/// cannot grow the process.
fn readStdin(gpa: std.mem.Allocator) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(gpa);
    var buf: [16 * 1024]u8 = undefined;
    while (list.items.len < 1024 * 1024) {
        const n = std.c.read(0, &buf, buf.len);
        if (n < 0) {
            if (std.c.errno(n) == .INTR) continue;
            break;
        }
        if (n == 0) break;
        try list.appendSlice(gpa, buf[0..@intCast(n)]);
    }
    return list.toOwnedSlice(gpa);
}

fn writeAll(fd: std.c.fd_t, data: []const u8) void {
    var at: usize = 0;
    while (at < data.len) {
        const n = std.c.write(fd, data[at..].ptr, data.len - at);
        if (n < 0) {
            if (std.c.errno(n) == .INTR) continue;
            return;
        }
        at += @intCast(n);
    }
}

fn fail(text: []const u8) u8 {
    writeAll(2, text);
    return 2;
}

test "unknown subcommand prints usage" {
    try std.testing.expect(std.mem.startsWith(u8, usage_text, "usage: cadex statusline"));
}
