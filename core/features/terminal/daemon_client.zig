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
    /// What the daemon speaks (wire.revision); 1 for one from before plan
    /// 39, which knows no join, size or guests frame.
    revision: u16 = 1,

    /// Connects and says hello. error.NoDaemon when nobody listens,
    /// error.Version when the daemon speaks another version.
    pub fn connect(gpa: std.mem.Allocator, path: []const u8) !Connection {
        const sock = wire.connect(path) orelse return error.NoDaemon;
        var self: Connection = .{ .sock = sock };
        errdefer self.deinit(gpa);
        var p: wire.Payload = .{ .gpa = gpa };
        defer p.deinit();
        try p.int(u16, wire.version);
        try p.int(u16, wire.revision);
        try self.send(gpa, .hello, p.bytes.items);
        const f = try self.next(gpa, 2000) orelse return error.Timeout;
        if (f.kind == .refused) return error.Version;
        if (f.kind != .hello_ok) return error.Protocol;
        var r: wire.Reader = .{ .rest = f.payload };
        _ = try r.int(u16);
        self.daemon_pid = try r.int(i32);
        self.revision = r.int(u16) catch 1;
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

    /// Watches and types in the session `id` beside the app that holds it
    /// (plan 39 A); the replay follows. error.Old from a daemon before it.
    pub fn join(self: *Connection, gpa: std.mem.Allocator, id: []const u8) !Ready {
        if (self.revision < 2) return error.Old;
        var p: wire.Payload = .{ .gpa = gpa };
        defer p.deinit();
        try p.string(id);
        try self.send(gpa, .join, p.bytes.items);
        return self.ready(gpa);
    }

    /// This screen's size; the daemon sets the smallest one on the pty.
    pub fn resize(self: *Connection, gpa: std.mem.Allocator, size: pty.Size) !void {
        var p: wire.Payload = .{ .gpa = gpa };
        defer p.deinit();
        try p.int(u16, size.cols);
        try p.int(u16, size.rows);
        try p.int(u16, size.cell_width_px);
        try p.int(u16, size.cell_height_px);
        try self.send(gpa, .size, p.bytes.items);
    }

    /// Ends the session (SIGHUP, then SIGKILL); a guest's close only lets go.
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

pub const Listed = struct { id: []const u8, pid: i32, alive: bool, exit_code: i32, attached: bool, guests: u8 = 0 };

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
        .guests = if (connection.revision >= 2) try r.int(u8) else 0,
    };
    return out;
}

/// The daemon answering on `socket`, started from `helper` when none does:
/// its own session (SETSID), no descriptor of the app's, its output to
/// /dev/null; a thread of the app reaps it when it leaves, so no zombie
/// stays while the app runs. Waits up to 5 s for the socket: once, right
/// after a build, a kept terminal gave up at 2 s and fell back to a pty of
/// its own (2026-11-15, not seen again in 10 runs).
pub fn ensure(helper: [*:0]const u8, socket: [*:0]const u8, scrollback: ?[*:0]const u8) !void {
    const path = std.mem.span(socket);
    if (wire.connect(path)) |fd| {
        _ = c.close(fd);
        return;
    }
    var actions: c.posix_spawn_file_actions_t = undefined;
    if (c.posix_spawn_file_actions_init(&actions) != 0) return error.SpawnFailed;
    defer _ = c.posix_spawn_file_actions_destroy(&actions);
    for ([_]c_int{ 0, 1, 2 }) |fd| _ = c.posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", @as(c_int, @bitCast(c.O{ .ACCMODE = .RDWR })), 0);
    var attr: c.posix_spawnattr_t = undefined;
    if (c.posix_spawnattr_init(&attr) != 0) return error.SpawnFailed;
    defer _ = c.posix_spawnattr_destroy(&attr);
    _ = c.posix_spawnattr_setflags(&attr, .{ .SETSID = true, .CLOEXEC_DEFAULT = true });
    var argv_scrollback = [_:null]?[*:0]const u8{ helper, "--socket", socket, "--scrollback", scrollback orelse "", null };
    var argv_plain = [_:null]?[*:0]const u8{ helper, "--socket", socket, null };
    const argv: [*:null]const ?[*:0]const u8 = if (scrollback != null) &argv_scrollback else &argv_plain;
    var pid: c.pid_t = 0;
    if (c.posix_spawn(&pid, helper, &actions, &attr, argv, c.environ) != 0) return error.SpawnFailed;
    if (std.Thread.spawn(.{}, reap, .{pid})) |t| t.detach() else |_| {}
    var waited: u32 = 0;
    while (waited < 5000) : (waited += 20) {
        if (wire.connect(path)) |fd| {
            _ = c.close(fd);
            return;
        }
        @import("../../shared/clock.zig").sleepMs(20);
    }
    return error.NoDaemon;
}

fn reap(pid: c.pid_t) void {
    var status: c_int = 0;
    while (c.waitpid(pid, &status, 0) < 0 and c.errno(@as(c_int, -1)) == .INTR) {}
}

/// Ends the daemon's sessions whose name starts with `prefix` (this app's)
/// and that no pane took back after a launch: nobody could see them again.
/// Returns how many.
pub fn closeUnclaimed(gpa: std.mem.Allocator, socket: []const u8, prefix: []const u8, claimed: []const []const u8) !usize {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var conn = try Connection.connect(gpa, socket);
    defer conn.deinit(gpa);
    const sessions = try list(gpa, arena.allocator(), &conn);
    var closed: usize = 0;
    for (sessions) |s| {
        if (!std.mem.startsWith(u8, s.id, prefix) or s.attached) continue;
        if (for (claimed) |id| (if (std.mem.eql(u8, id, s.id)) break true) else false) continue;
        var one = Connection.connect(gpa, socket) catch continue;
        defer one.deinit(gpa);
        _ = one.attach(gpa, s.id) catch continue;
        one.close(gpa) catch continue;
        closed += 1;
    }
    return closed;
}
