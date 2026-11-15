//! `cadex-terminald`, the terminal daemon's program (docs/adr/0022-terminal-daemon.md):
//! the app starts it when terminal.keepSessions is on; it leaves its
//! session (setsid) so the app's end does not reach it, ignores SIGHUP,
//! listens on terminal.sock and runs until it has no session and no app.
//! A daemon already answering there wins: this one leaves with 0.

const std = @import("std");
const c = std.c;
const wire = @import("daemon_wire.zig");
const daemon = @import("daemon.zig");

const usage_text = "usage: cadex-terminald [--socket <path>] [--scrollback <folder>]\n";

extern "c" fn signal(sig: c_int, handler: usize) usize;
const sighup: c_int = 1;
const sig_ign: usize = 1;

pub fn main(init: std.process.Init.Minimal) u8 {
    var args = init.args.iterate();
    _ = args.next();
    var path_buf: [104]u8 = undefined;
    var path: []const u8 = defaultPath(&path_buf) orelse return fail("no HOME\n");
    var scrollback: ?[]const u8 = null;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--socket")) {
            path = args.next() orelse return fail(usage_text);
        } else if (std.mem.eql(u8, arg, "--scrollback")) {
            scrollback = args.next() orelse return fail(usage_text);
        } else return fail(usage_text);
    }
    _ = c.setsid();
    _ = signal(sighup, sig_ign);
    makeFolder(path);

    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    var server = daemon.Server.listen(gpa_state.allocator(), path) catch |err| switch (err) {
        error.Running => return 0,
        else => return fail("could not listen on the socket\n"),
    };
    defer server.deinit();
    server.scrollback_dir = scrollback;
    server.run() catch return 1;
    var z: [105]u8 = @splat(0);
    @memcpy(z[0..path.len], path);
    _ = c.unlink(@ptrCast(&z));
    return 0;
}

/// `~/Library/Application Support/Cadex/sockets/terminal-<version>.sock`:
/// the version in the name lets an updated app with another protocol
/// start its own daemon while the old one keeps its sessions.
pub fn defaultPath(out: []u8) ?[]const u8 {
    const home = std.mem.span(c.getenv("HOME") orelse return null);
    return std.fmt.bufPrint(out, "{s}/Library/Application Support/Cadex/sockets/terminal-{d}.sock", .{ home, wire.version }) catch null;
}

/// The socket's folder, 0700 (docs/adr/0022-terminal-daemon.md).
fn makeFolder(path: []const u8) void {
    const dir = std.fs.path.dirname(path) orelse return;
    var z: [105]u8 = @splat(0);
    if (dir.len >= z.len) return;
    @memcpy(z[0..dir.len], dir);
    // The parents (Application Support/Cadex) as usual, the last one 0700.
    var i: usize = 1;
    while (i < dir.len) : (i += 1) if (z[i] == '/') {
        z[i] = 0;
        _ = c.mkdir(@ptrCast(&z), 0o755);
        z[i] = '/';
    };
    _ = c.mkdir(@ptrCast(&z), 0o700);
}

fn fail(text: []const u8) u8 {
    _ = c.write(2, text.ptr, text.len);
    return 2;
}
