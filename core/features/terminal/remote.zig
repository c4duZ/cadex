//! The terminal feature's door for another program (plan 39 B,
//! docs/plans/39-terminals-from-the-phone.md): `cadex attach` lists the
//! daemon's sessions and joins one as a second screen. Only the daemon's
//! client and protocol, no libghostty: the phone's terminal draws.

const std = @import("std");
const c = std.c;
const client = @import("daemon_client.zig");
const wire = @import("daemon_wire.zig");

pub const Connection = client.Connection;
pub const Listed = client.Listed;
pub const Size = @import("pty.zig").Size;
pub const list = client.list;
pub const writeAll = wire.writeAll;
pub const Reader = wire.Reader;

/// The daemon's socket, as the app finds it (TerminalDaemon.swift):
/// CADEX_TERMINAL_SOCKET (a test instance's), else the one in Cadex's
/// sockets folder with the protocol's version in the name.
pub fn socketPath(out: []u8) ?[]const u8 {
    if (c.getenv("CADEX_TERMINAL_SOCKET")) |value| {
        const path = std.mem.span(value);
        if (path.len == 0 or path.len > out.len) return null;
        @memcpy(out[0..path.len], path);
        return out[0..path.len];
    }
    const home = std.mem.span(c.getenv("HOME") orelse return null);
    return std.fmt.bufPrint(out, "{s}/Library/Application Support/Cadex/sockets/terminal-{d}.sock", .{ home, wire.version }) catch null;
}
