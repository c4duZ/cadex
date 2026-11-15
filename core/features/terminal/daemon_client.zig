//! The app's side of terminal.sock (docs/adr/0022-terminal-daemon.md): one
//! connection per pane, bound to one session. Plan 19 phase E1 uses it in
//! the tests; in E2 a session of the app reads through it in place of a
//! pty it started itself. Blocking, with time limits.

const std = @import("std");
const c = std.c;
const wire = @import("daemon_wire.zig");
const pty = @import("pty.zig");

pub const Connection = struct {
    sock: c_int,
    inbox: wire.Inbox = .{},
    /// The pty's master, from "ready" while the program runs; the app's own
    /// copy: writes, resizes and the foreground program go through it.
    master: ?c_int = null,
    daemon_pid: i32 = 0,

    /// Connects and says hello. error.NoDaemon when nobody listens,
    /// error.Version when the daemon speaks another version.
    pub fn connect(gpa: std.mem.Allocator, path: []const u8) !Connection {
        const sock = wire.connect(path) orelse return error.NoDaemon;
        var self: Connection = .{ .sock = sock };
        errdefer self.deinit(gpa);
        var p: wire.Payload = .{ .gpa = gpa };
        defer p.deinit();
        try p.int(u16, wire.version);
        try self.send(gpa, .hello, p.bytes.items);
        const f = try self.next(gpa, 2000) orelse return error.Timeout;
        if (f.kind == .refused) return error.Version;
        if (f.kind != .hello_ok) return error.Protocol;
        var r: wire.Reader = .{ .rest = f.payload };
        _ = try r.int(u16);
        self.daemon_pid = try r.int(i32);
        return self;
    }

    /// Lets go: the session keeps running in the daemon.
    pub fn deinit(self: *Connection, gpa: std.mem.Allocator) void {
        if (self.master) |fd| _ = c.close(fd);
        _ = c.close(self.sock);
        self.inbox.deinit(gpa);
    }

    pub fn send(self: *Connection, gpa: std.mem.Allocator, kind: wire.Kind, payload: []const u8) !void {
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(gpa);
        try wire.frame(gpa, &out, kind, payload);
        try wire.writeAll(self.sock, out.items);
    }

    /// The next frame within `ms` (-1: no limit), or null; valid until the
    /// next call. error.Closed when the daemon went away.
    pub fn next(self: *Connection, gpa: std.mem.Allocator, ms: i32) !?wire.Frame {
        while (true) {
            if (try self.inbox.next()) |f| return f;
            var fds = [_]c.pollfd{.{ .fd = self.sock, .events = c.POLL.IN, .revents = 0 }};
            if (c.poll(&fds, 1, ms) <= 0) return null;
            const room = try self.inbox.room(gpa, wire.chunk);
            const n = (try wire.receive(self.sock, room, &self.master)) orelse continue;
            if (n == 0) return error.Closed;
            self.inbox.filled(n);
        }
    }

    /// A new session named `id`; its "ready" or the daemon's refusal.
    pub fn open(self: *Connection, gpa: std.mem.Allocator, id: []const u8, size: pty.Size, cwd: []const u8, shell: []const u8) !Ready {
        var p: wire.Payload = .{ .gpa = gpa };
        defer p.deinit();
        try p.int(u16, size.cols);
        try p.int(u16, size.rows);
        try p.int(u16, size.cell_width_px);
        try p.int(u16, size.cell_height_px);
        try p.int(u32, 0);
        try p.string(id);
        try p.string(cwd);
        try p.string(shell);
        try self.send(gpa, .open, p.bytes.items);
        return self.ready(gpa);
    }

    /// Takes the session `id` back; the replay follows as output frames.
    pub fn attach(self: *Connection, gpa: std.mem.Allocator, id: []const u8) !Ready {
        var p: wire.Payload = .{ .gpa = gpa };
        defer p.deinit();
        try p.string(id);
        try self.send(gpa, .attach, p.bytes.items);
        return self.ready(gpa);
    }

    /// Ends the session (SIGHUP, then SIGKILL).
    pub fn close(self: *Connection, gpa: std.mem.Allocator) !void {
        try self.send(gpa, .close, "");
    }

    fn ready(self: *Connection, gpa: std.mem.Allocator) !Ready {
        const f = try self.next(gpa, 5000) orelse return error.Timeout;
        if (f.kind == .refused) return error.Refused;
        if (f.kind != .ready) return error.Protocol;
        var r: wire.Reader = .{ .rest = f.payload };
        return .{ .pid = try r.int(i32), .alive = try r.int(u8) != 0, .exit_code = try r.int(i32) };
    }
};

pub const Ready = struct { pid: i32, alive: bool, exit_code: i32 };

pub const Listed = struct { id: []const u8, pid: i32, alive: bool, exit_code: i32, attached: bool };

/// The daemon's sessions; strings live in `arena`, the connection's
/// buffers in `gpa`.
pub fn list(gpa: std.mem.Allocator, arena: std.mem.Allocator, connection: *Connection) ![]Listed {
    try connection.send(gpa, .list, "");
    const f = try connection.next(gpa, 2000) orelse return error.Timeout;
    if (f.kind != .sessions) return error.Protocol;
    var r: wire.Reader = .{ .rest = f.payload };
    const count = try r.int(u32);
    const out = try arena.alloc(Listed, count);
    for (out) |*item| item.* = .{
        .id = try arena.dupe(u8, try r.string()),
        .pid = try r.int(i32),
        .alive = try r.int(u8) != 0,
        .exit_code = try r.int(i32),
        .attached = try r.int(u8) != 0,
    };
    return out;
}
