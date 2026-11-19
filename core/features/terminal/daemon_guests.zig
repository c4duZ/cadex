//! A second screen on a session (plan 39 A, docs/plans/39-terminals-from-the-phone.md):
//! a guest joins a session the app holds (the owner's phone, by `cadex
//! attach` over SSH), gets the replay and every new output, and types on the
//! pty's master as the app does. Neither takes the session from the other.
//! The pty takes the smallest size among them, as tmux does, and goes back
//! to the app's once the guest leaves. The app hears how many guests there
//! are, for the tab's mark.

const std = @import("std");
const wire = @import("daemon_wire.zig");
const state = @import("daemon_state.zig");
const daemon = @import("daemon.zig");
const handle = @import("daemon_handle.zig");
const pty = @import("pty.zig");
const Server = daemon.Server;
const Session = state.Session;
const Client = state.Client;

/// join: the session's id. The same "ready", master and replay as an attach.
pub fn join(server: *Server, client: *Client, id: []const u8) !void {
    if (client.session != null) return client.refuse(server.gpa, "busy");
    const s = server.find(id) orelse return client.refuse(server.gpa, "unknown");
    try handle.bind(server, client, s, true);
    tellCount(server, s);
}

/// size: cols, rows, cell width and height in pixels (u16 each).
pub fn resize(client: *Client, r: *wire.Reader) !void {
    client.size = .{
        .cols = try r.int(u16),
        .rows = try r.int(u16),
        .cell_width_px = try r.int(u16),
        .cell_height_px = try r.int(u16),
    };
    if (client.session) |s| apply(s);
}

/// The guest goes (it closed, or its connection ended): the session runs on,
/// and the pty grows back to the screens left.
pub fn leave(server: *Server, client: *Client) void {
    const s = client.session orelse return;
    client.session = null;
    client.guest = false;
    for (s.guests.items, 0..) |item, i| if (item == client) {
        _ = s.guests.swapRemove(i);
        break;
    };
    apply(s);
    tellCount(server, s);
}

/// New output to each guest. A guest that fell this far behind (a phone on
/// a bad network) is let go instead of holding the program, which the app
/// would feel: its connection closes and `cadex attach` can join again.
pub fn fanOut(server: *Server, s: *Session, bytes: []const u8) void {
    var i: usize = s.guests.items.len;
    while (i > 0) {
        i -= 1;
        const guest = s.guests.items[i];
        guest.sendOutput(server.gpa, bytes) catch {};
        if (guest.pending() > state.backlog_limit) {
            guest.outbox.clearRetainingCapacity();
            guest.sent = 0;
            guest.closing = true;
            leave(server, guest);
        }
    }
}

/// The program ended: each guest hears it, as the app does.
pub fn tellExited(server: *Server, s: *Session) void {
    var p: wire.Payload = .{ .gpa = server.gpa };
    defer p.deinit();
    p.int(i32, s.exit_code orelse -1) catch return;
    for (s.guests.items) |guest| guest.send(server.gpa, .exited, p.bytes.items) catch {};
}

/// The session goes away: its guests let go, and their connections close
/// once what they were sent is out.
pub fn detachAll(s: *Session) void {
    for (s.guests.items) |guest| {
        guest.session = null;
        guest.guest = false;
        guest.closing = true;
    }
    s.guests.clearRetainingCapacity();
}

/// The pty takes the smallest of the screens that said their size (an app
/// of revision 1 says none: it resizes on its own, as before).
pub fn apply(s: *Session) void {
    const want = smallest(s) orelse return;
    if (!s.alive() or s.master < 0) return;
    if (s.size) |now| if (std.meta.eql(now, want)) return;
    (pty.Child{ .fd = s.master, .pid = s.pid }).resize(want) catch return;
    s.size = want;
}

pub fn smallest(s: *const Session) ?pty.Size {
    var out: ?pty.Size = if (s.client) |owner| owner.size else null;
    for (s.guests.items) |guest| {
        const size = guest.size orelse continue;
        out = if (out) |o| .{
            .cols = @min(o.cols, size.cols),
            .rows = @min(o.rows, size.rows),
            .cell_width_px = if (size.cols < o.cols) size.cell_width_px else o.cell_width_px,
            .cell_height_px = if (size.rows < o.rows) size.cell_height_px else o.cell_height_px,
        } else size;
    }
    return out;
}

/// To the app holding the session, when it speaks revision 2: the guests.
pub fn tellCount(server: *Server, s: *Session) void {
    const owner = s.client orelse return;
    if (owner.revision < 2) return;
    var p: wire.Payload = .{ .gpa = server.gpa };
    defer p.deinit();
    p.int(u8, @intCast(@min(s.guests.items.len, 255))) catch return;
    owner.send(server.gpa, .guests, p.bytes.items) catch {};
}
