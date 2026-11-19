//! Inside a joined session (plan 39 B): the phone's terminal in raw mode,
//! its keys to the pty's master, the session's output to the screen, its
//! size to the daemon. Ctrl+\ then d leaves without closing anything (as
//! tmux's prefix and d); closing the SSH app leaves too.

const std = @import("std");
const c = std.c;
const remote = @import("../terminal/remote.zig");
const replies = @import("attach_replies.zig");

/// Ctrl+\ : the next key is ours (d leaves; Ctrl+\ again sends one).
pub const prefix = 0x1c;

pub const End = enum { left, exited, lost };

extern "c" fn cfmakeraw(termios_p: *c.termios) void;
extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;
/// _IOR('t', 104, struct winsize) on macOS.
const TIOCGWINSZ: c_ulong = 0x40087468;
const Winsize = extern struct { row: u16, col: u16, xpixel: u16, ypixel: u16 };

/// The screen's size now, null when stdout is not a terminal.
pub fn screenSize() ?remote.Size {
    var ws: Winsize = undefined;
    if (ioctl(1, TIOCGWINSZ, &ws) != 0 or ws.col == 0) return null;
    return .{ .cols = ws.col, .rows = ws.row, .cell_width_px = 0, .cell_height_px = 0 };
}

/// Runs until the owner leaves, the program ends or the daemon goes;
/// the terminal is put back as it was, and the exit code is in `code`.
pub fn run(gpa: std.mem.Allocator, conn: *remote.Connection, code: *i32) End {
    var saved: c.termios = undefined;
    const raw = c.tcgetattr(0, &saved) == 0;
    if (raw) {
        var t = saved;
        cfmakeraw(&t);
        _ = c.tcsetattr(0, .NOW, &t);
    }
    defer {
        if (raw) _ = c.tcsetattr(0, .NOW, &saved);
        // What the session's program may have left on: the other screen,
        // the mouse, bracketed paste, a hidden cursor, colors.
        remote.writeAll(1, "\x1b[?1049l\x1b[?1000l\x1b[?1002l\x1b[?1003l\x1b[?1006l\x1b[?2004l\x1b[?25h\x1b[0m\r\n") catch {};
    }
    var size = screenSize();
    if (size) |s| conn.resize(gpa, s) catch {};
    var pending_prefix = false;
    while (true) {
        var fds = [_]c.pollfd{
            .{ .fd = 0, .events = c.POLL.IN, .revents = 0 },
            .{ .fd = conn.sock, .events = c.POLL.IN, .revents = 0 },
        };
        _ = c.poll(&fds, fds.len, 250);
        // The screen turned or the window changed: no SIGWINCH handler,
        // a look every quarter second is enough.
        const now = screenSize();
        if (now != null and (size == null or !std.meta.eql(now.?, size.?))) {
            size = now;
            conn.resize(gpa, now.?) catch {};
        }
        if (fds[1].revents != 0) {
            while (true) {
                const f = (conn.next(gpa, 0) catch return .lost) orelse break;
                switch (f.kind) {
                    .output => remote.writeAll(1, f.payload) catch return .lost,
                    .exited => {
                        var r: remote.Reader = .{ .rest = f.payload };
                        code.* = r.int(i32) catch -1;
                        return .exited;
                    },
                    else => {},
                }
            }
        }
        if (fds[0].revents != 0) {
            var buf: [4096]u8 = undefined;
            const n = c.read(0, &buf, buf.len);
            if (n == 0) return .left;
            if (n < 0) {
                if (c.errno(n) == .INTR or c.errno(n) == .AGAIN) continue;
                return .left;
            }
            var clean: [4096]u8 = undefined;
            var out: [4096 * 2]u8 = undefined;
            const typed = keys(replies.strip(buf[0..@intCast(n)], &clean), &pending_prefix, &out) orelse return .left;
            const master = conn.master orelse return .lost;
            if (typed.len > 0) remote.writeAll(master, typed) catch return .lost;
        }
    }
}

/// The keys to send, with the prefix taken out; null when the owner leaves.
pub fn keys(input: []const u8, pending: *bool, out: []u8) ?[]const u8 {
    var n: usize = 0;
    for (input) |b| {
        if (pending.*) {
            pending.* = false;
            if (b == 'd' or b == 'D') return null;
            out[n] = prefix;
            n += 1;
            if (b == prefix) continue;
        } else if (b == prefix) {
            pending.* = true;
            continue;
        }
        out[n] = b;
        n += 1;
    }
    return out[0..n];
}

test "Ctrl+\\ then d leaves; Ctrl+\\ twice sends one; other keys pass" {
    const t = std.testing;
    var out: [16]u8 = undefined;
    var pending = false;
    try t.expectEqualStrings("ls\r", keys("ls\r", &pending, &out).?);
    try t.expect(keys("x\x1cd", &pending, &out) == null);
    pending = false;
    try t.expectEqualStrings("\x1c", keys("\x1c\x1c", &pending, &out).?);
    try t.expectEqualStrings("", keys("\x1c", &pending, &out).?);
    try t.expect(pending);
    try t.expectEqualStrings("\x1ca", keys("a", &pending, &out).?);
}
