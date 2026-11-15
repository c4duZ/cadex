//! What the terminal daemon holds (docs/adr/0022-terminal-daemon.md): each
//! session's pty, its kept output and modes, and each connection of the app
//! with what it still has to receive. The loop is `daemon.zig`.

const std = @import("std");
const c = std.c;
const wire = @import("daemon_wire.zig");
const Ring = @import("daemon_ring.zig").Ring;
const Modes = @import("daemon_modes.zig").Modes;

pub const Session = struct {
    /// The app's name for it (a pane's id); unique in the daemon.
    id: []u8,
    pid: c.pid_t,
    /// The pty's master; -1 once drained after the program ended.
    master: c_int,
    ring: Ring = .{},
    modes: Modes = .{},
    exit_code: ?i32 = null,
    client: ?*Client = null,
    /// The app closed it: SIGKILL at this time if SIGHUP did not end it.
    kill_at: ?i64 = null,
    /// An attached app was told it ended: it goes when that app lets go.
    exit_told: bool = false,

    pub fn alive(self: *const Session) bool {
        return self.exit_code == null;
    }

    pub fn destroy(self: *Session, gpa: std.mem.Allocator) void {
        if (self.master >= 0) _ = c.close(self.master);
        self.ring.deinit(gpa);
        gpa.free(self.id);
        gpa.destroy(self);
    }

    /// What an attach replays: the kept output, then the modes it misses.
    pub fn replay(self: *const Session, gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
        try out.appendSlice(gpa, self.ring.contents());
        var replayed: Modes = .{};
        replayed.feed(self.ring.contents());
        try self.modes.suffix(&replayed, out, gpa);
    }
};

/// Above this much unsent output the daemon stops reading the attached
/// session's pty, so a stuck app slows the program instead of growing
/// the daemon (the kernel's pty buffer then holds the program).
pub const backlog_limit = 8 * 1024 * 1024;

pub const Client = struct {
    fd: c_int,
    inbox: wire.Inbox = .{},
    outbox: std.ArrayList(u8) = .empty,
    sent: usize = 0,
    said_hello: bool = false,
    session: ?*Session = null,
    /// Close once the outbox is out (a refused hello).
    closing: bool = false,

    pub fn destroy(self: *Client, gpa: std.mem.Allocator) void {
        _ = c.close(self.fd);
        self.inbox.deinit(gpa);
        self.outbox.deinit(gpa);
        gpa.destroy(self);
    }

    pub fn pending(self: *const Client) usize {
        return self.outbox.items.len - self.sent;
    }

    pub fn send(self: *Client, gpa: std.mem.Allocator, kind: wire.Kind, payload: []const u8) !void {
        try wire.frame(gpa, &self.outbox, kind, payload);
    }

    /// Output in frames of at most wire.chunk.
    pub fn sendOutput(self: *Client, gpa: std.mem.Allocator, bytes: []const u8) !void {
        var rest = bytes;
        while (rest.len > 0) {
            const n = @min(rest.len, wire.chunk);
            try self.send(gpa, .output, rest[0..n]);
            rest = rest[n..];
        }
    }

    pub fn refuse(self: *Client, gpa: std.mem.Allocator, reason: []const u8) !void {
        var p: wire.Payload = .{ .gpa = gpa };
        defer p.deinit();
        try p.string(reason);
        try self.send(gpa, .refused, p.bytes.items);
    }

    /// Writes what it can without blocking; false when the app went away.
    pub fn flush(self: *Client, gpa: std.mem.Allocator) bool {
        while (self.pending() > 0) {
            const rest = self.outbox.items[self.sent..];
            const n = c.write(self.fd, rest.ptr, rest.len);
            if (n < 0) switch (c.errno(n)) {
                .INTR => continue,
                .AGAIN => break,
                else => return false,
            };
            self.sent += @intCast(n);
        }
        if (self.pending() == 0) {
            self.outbox.clearRetainingCapacity();
            self.sent = 0;
        } else if (self.sent > wire.chunk * 4) {
            const left = self.pending();
            std.mem.copyForwards(u8, self.outbox.items[0..left], self.outbox.items[self.sent..]);
            self.outbox.shrinkRetainingCapacity(left);
            self.sent = 0;
        }
        _ = gpa;
        return true;
    }
};

/// "ready" for `session`: its pid, whether it runs, the exit code.
pub fn readyPayload(gpa: std.mem.Allocator, session: *const Session) !wire.Payload {
    var p: wire.Payload = .{ .gpa = gpa };
    errdefer p.deinit();
    try p.int(i32, session.pid);
    try p.int(u8, @intFromBool(session.alive()));
    try p.int(i32, session.exit_code orelse 0);
    return p;
}

/// "sessions": the count, then id, pid, running, exit code and attached.
pub fn sessionsPayload(gpa: std.mem.Allocator, sessions: []const *Session) !wire.Payload {
    var p: wire.Payload = .{ .gpa = gpa };
    errdefer p.deinit();
    try p.int(u32, @intCast(sessions.len));
    for (sessions) |s| {
        try p.string(s.id);
        try p.int(i32, s.pid);
        try p.int(u8, @intFromBool(s.alive()));
        try p.int(i32, s.exit_code orelse 0);
        try p.int(u8, @intFromBool(s.client != null));
    }
    return p;
}
