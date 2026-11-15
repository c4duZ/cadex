//! What the terminal daemon does with each frame from the app
//! (docs/adr/0022-terminal-daemon.md): the hello with the version, opening
//! a session, attaching to one (the master, the replay, the end if it
//! ended), the list and closing. A connection holds at most one session.

const std = @import("std");
const c = std.c;
const wire = @import("daemon_wire.zig");
const state = @import("daemon_state.zig");
const daemon = @import("daemon.zig");
const Server = daemon.Server;
const Session = state.Session;
const Client = state.Client;
const pty = @import("pty.zig");
const clock = @import("../../shared/clock.zig");

/// Reads what the app sent and answers it; false when the app went away
/// or broke the protocol.
pub fn readClient(server: *Server, client: *Client) bool {
    const gpa = server.gpa;
    while (true) {
        const room = client.inbox.room(gpa, wire.chunk) catch return false;
        const n = c.read(client.fd, room.ptr, room.len);
        if (n == 0) return false;
        if (n < 0) switch (c.errno(n)) {
            .INTR => continue,
            .AGAIN => break,
            else => return false,
        };
        client.inbox.filled(@intCast(n));
    }
    while (true) {
        const f = (client.inbox.next() catch return false) orelse return true;
        answer(server, client, f) catch return false;
    }
}

fn answer(server: *Server, client: *Client, f: wire.Frame) !void {
    const gpa = server.gpa;
    var r: wire.Reader = .{ .rest = f.payload };
    if (!client.said_hello) {
        if (f.kind != .hello) return error.NoHello;
        const theirs = try r.int(u16);
        if (theirs != wire.version) {
            try client.refuse(gpa, "version");
            client.closing = true;
            return;
        }
        client.said_hello = true;
        var p: wire.Payload = .{ .gpa = gpa };
        defer p.deinit();
        try p.int(u16, wire.version);
        try p.int(i32, c.getpid());
        return client.send(gpa, .hello_ok, p.bytes.items);
    }
    switch (f.kind) {
        .open => try open(server, client, &r),
        .attach => try attach(server, client, try r.string()),
        .list => {
            var p = try state.sessionsPayload(gpa, server.sessions.items);
            defer p.deinit();
            try client.send(gpa, .sessions, p.bytes.items);
        },
        .close => if (client.session) |s| {
            client.session = null;
            s.client = null;
            if (s.alive()) hangUp(s) else server.remove(s);
        },
        else => return error.UnknownFrame,
    }
}

/// open: cols, rows, cell width and height in pixels (u16 each), the
/// ring's limit (u32, 0 = default), then the id, the folder and the shell.
fn open(server: *Server, client: *Client, r: *wire.Reader) !void {
    const gpa = server.gpa;
    const size: pty.Size = .{
        .cols = try r.int(u16),
        .rows = try r.int(u16),
        .cell_width_px = try r.int(u16),
        .cell_height_px = try r.int(u16),
    };
    const limit = try r.int(u32);
    const id = try r.string();
    const cwd = try r.string();
    const shell = try r.string();
    if (client.session != null) return client.refuse(gpa, "busy");
    if (id.len == 0 or server.find(id) != null) return client.refuse(gpa, "id");
    const s = openSession(server, id, size, if (cwd.len > 0) cwd else null, if (shell.len > 0) shell else null, limit) catch
        return client.refuse(gpa, "spawn");
    try bind(server, client, s);
}

fn attach(server: *Server, client: *Client, id: []const u8) !void {
    const gpa = server.gpa;
    if (client.session != null) return client.refuse(gpa, "busy");
    const s = server.find(id) orelse return client.refuse(gpa, "unknown");
    // The newest app wins: an older connection still holding it lets go.
    if (s.client) |old| {
        old.session = null;
        old.closing = true;
        s.client = null;
    }
    try bind(server, client, s);
}

/// "ready" (with the master while the program runs), the replay, and
/// "exited" when it ended already.
fn bind(server: *Server, client: *Client, s: *Session) !void {
    const gpa = server.gpa;
    var p = try state.readyPayload(gpa, s);
    defer p.deinit();
    if (s.alive() and s.master >= 0) {
        // The fd must leave with these bytes, so they skip the outbox:
        // flush what is queued first (blocking for a moment is fine here).
        while (client.pending() > 0) {
            if (!client.flush(gpa)) return error.Gone;
            if (client.pending() > 0 and !wire.waitWritable(client.fd, 1000)) return error.Gone;
        }
        var ready: std.ArrayList(u8) = .empty;
        defer ready.deinit(gpa);
        try wire.frame(gpa, &ready, .ready, p.bytes.items);
        try wire.sendWithFd(client.fd, ready.items, s.master);
    } else try client.send(gpa, .ready, p.bytes.items);
    client.session = s;
    s.client = client;
    var replay: std.ArrayList(u8) = .empty;
    defer replay.deinit(gpa);
    try s.replay(gpa, &replay);
    try client.sendOutput(gpa, replay.items);
    if (!s.alive()) {
        var e: wire.Payload = .{ .gpa = gpa };
        defer e.deinit();
        try e.int(i32, s.exit_code.?);
        try client.send(gpa, .exited, e.bytes.items);
        s.exit_told = true;
    }
}

fn openSession(self: *Server, id: []const u8, size: pty.Size, cwd: ?[]const u8, shell: ?[]const u8, ring_limit: u32) !*Session {
    const child = try pty.Child.start(self.gpa, .{ .size = size, .cwd = cwd, .shell = shell });
    errdefer child.kill();
    wire.setNonblocking(child.fd);
    const s = try self.gpa.create(Session);
    errdefer self.gpa.destroy(s);
    s.* = .{ .id = try self.gpa.dupe(u8, id), .pid = child.pid, .master = child.fd };
    if (ring_limit > 0) s.ring.limit = ring_limit;
    try self.sessions.append(self.gpa, s);
    return s;
}

/// The app closed the session: SIGHUP now, SIGKILL after the grace.
fn hangUp(s: *Session) void {
    _ = c.kill(s.pid, .HUP);
    s.kill_at = clock.monotonicMs() + daemon.hangup_grace_ms;
}
