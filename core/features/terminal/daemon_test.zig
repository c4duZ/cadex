//! The terminal daemon with real shells (/bin/sh standing in for the user's)
//! on a socket of its own, the loop on a thread, and the app played by
//! `daemon_client.zig` (plan 19 phase E1).

const std = @import("std");
const c = std.c;
const testing = std.testing;
const clock = @import("../../shared/clock.zig");
const daemon = @import("daemon.zig");
const client = @import("daemon_client.zig");
const wire = @import("daemon_wire.zig");

const size: @import("pty.zig").Size = .{ .cols = 80, .rows = 24 };

pub const Running = struct {
    server: daemon.Server,
    thread: std.Thread = undefined,
    path_buf: [64]u8 = undefined,
    path: []const u8 = "",
    result: ?anyerror = null,

    pub fn start(self: *Running, name: []const u8) !void {
        self.path = try std.fmt.bufPrint(&self.path_buf, "/tmp/cadex-td-{d}-{s}.sock", .{ c.getpid(), name });
        self.server = try daemon.Server.listen(testing.allocator, self.path);
        self.thread = try std.Thread.spawn(.{}, loop, .{self});
    }

    fn loop(self: *Running) void {
        self.server.run() catch |err| {
            self.result = err;
        };
    }

    /// Waits for the loop to end on its own (idle), or stops it.
    pub fn finish(self: *Running, expect_idle: bool) !void {
        if (!expect_idle) self.server.requestStop();
        self.thread.join();
        self.server.deinit();
        var z: [65]u8 = @splat(0);
        @memcpy(z[0..self.path.len], self.path);
        _ = c.unlink(@ptrCast(&z));
        if (self.result) |err| return err;
    }
};

/// Output frames until `needle` shows up in them, within ~5 s.
pub fn waitOutput(conn: *client.Connection, needle: []const u8) !void {
    var seen: std.ArrayList(u8) = .empty;
    defer seen.deinit(testing.allocator);
    const deadline = clock.monotonicMs() + 5000;
    while (clock.monotonicMs() < deadline) {
        const f = try conn.next(testing.allocator, 100) orelse continue;
        if (f.kind == .output) try seen.appendSlice(testing.allocator, f.payload);
        if (std.mem.indexOf(u8, seen.items, needle) != null) return;
    }
    return error.NeverSaw;
}

/// The exit code from the next "exited" frame, within ~5 s.
pub fn waitExit(conn: *client.Connection) !i32 {
    const deadline = clock.monotonicMs() + 5000;
    while (clock.monotonicMs() < deadline) {
        const f = try conn.next(testing.allocator, 100) orelse continue;
        if (f.kind == .exited) {
            var r: wire.Reader = .{ .rest = f.payload };
            return r.int(i32);
        }
    }
    return error.NeverExited;
}

pub fn type_(conn: *client.Connection, text: []const u8) !void {
    try wire.writeAll(conn.master.?, text);
}

test "a session outlives its app: detach, attach again with the replay, end" {
    var d: Running = .{ .server = undefined };
    try d.start("life");
    {
        var app = try client.Connection.connect(testing.allocator, d.path);
        defer app.deinit(testing.allocator);
        const ready = try app.open(testing.allocator, "pane-1", size, "/tmp", "/bin/sh");
        try testing.expect(ready.alive and ready.pid > 0 and app.master != null);
        // Arithmetic, so the match is the shell's output and not the echo.
        try type_(&app, "echo kept-$((40+2))\n");
        try waitOutput(&app, "kept-42");
        // A second open of the same name is refused.
        var other = try client.Connection.connect(testing.allocator, d.path);
        defer other.deinit(testing.allocator);
        try testing.expectError(error.Refused, other.open(testing.allocator, "pane-1", size, "", "/bin/sh"));
    }
    // The app went away (closed, crashed): the shell is still there.
    var app = try client.Connection.connect(testing.allocator, d.path);
    defer app.deinit(testing.allocator);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const listed = try client.list(testing.allocator, arena.allocator(), &app);
    try testing.expect(listed.len == 1 and listed[0].alive and !listed[0].attached);
    try testing.expect(c.kill(listed[0].pid, @enumFromInt(0)) == 0);
    const back = try app.attach(testing.allocator, "pane-1");
    try testing.expect(back.alive and app.master != null);
    try waitOutput(&app, "kept-42");
    try type_(&app, "echo again-$((1+1)); exit 3\n");
    try waitOutput(&app, "again-2");
    try testing.expectEqual(@as(i32, 3), try waitExit(&app));
    // Told and let go: the ended session is gone. A second app connects
    // first, or the daemon would leave as soon as the last one does.
    var second = try client.Connection.connect(testing.allocator, d.path);
    app.deinit(testing.allocator);
    app = .{ .sock = -1 };
    var gone = false;
    var waited: u32 = 0;
    while (!gone and waited < 2000) : (waited += 20) {
        clock.sleepMs(20);
        gone = (try client.list(testing.allocator, arena.allocator(), &second)).len == 0;
    }
    try testing.expect(gone);
    // No session and now no app: the daemon leaves by itself.
    second.deinit(testing.allocator);
    try d.finish(true);
}

test "a session that ended with no app keeps its output and code for the next attach" {
    var d: Running = .{ .server = undefined };
    try d.start("ended");
    {
        var app = try client.Connection.connect(testing.allocator, d.path);
        defer app.deinit(testing.allocator);
        _ = try app.open(testing.allocator, "pane-2", size, "", "/bin/sh");
        try type_(&app, "sleep 0.3; echo last-$((2+2)); exit 4\n");
    }
    clock.sleepMs(900);
    var app = try client.Connection.connect(testing.allocator, d.path);
    defer app.deinit(testing.allocator);
    const back = try app.attach(testing.allocator, "pane-2");
    try testing.expect(!back.alive and back.exit_code == 4 and app.master == null);
    try waitOutput(&app, "last-4");
    try testing.expectEqual(@as(i32, 4), try waitExit(&app));
    try d.finish(false);
}

test "closing a session ends its program; a second daemon on the same socket is refused" {
    var d: Running = .{ .server = undefined };
    try d.start("close");
    var app = try client.Connection.connect(testing.allocator, d.path);
    defer app.deinit(testing.allocator);
    const ready = try app.open(testing.allocator, "pane-3", size, "", "/bin/sh");
    try testing.expectError(error.Running, daemon.Server.listen(testing.allocator, d.path));
    try app.close(testing.allocator);
    var gone = false;
    var waited: u32 = 0;
    while (waited < 2000 and !gone) : (waited += 20) {
        clock.sleepMs(20);
        var arena: std.heap.ArenaAllocator = .init(testing.allocator);
        defer arena.deinit();
        var probe = try client.Connection.connect(testing.allocator, d.path);
        defer probe.deinit(testing.allocator);
        gone = (try client.list(testing.allocator, arena.allocator(), &probe)).len == 0;
    }
    try testing.expect(gone);
    try testing.expect(c.kill(ready.pid, @enumFromInt(0)) != 0);
    try d.finish(false);
}

test "a hello of another version is refused" {
    var d: Running = .{ .server = undefined };
    try d.start("version");
    const sock = wire.connect(d.path).?;
    defer _ = c.close(sock);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);
    try wire.frame(testing.allocator, &out, .hello, &.{ 99, 0 });
    try wire.writeAll(sock, out.items);
    var conn: client.Connection = .{ .sock = sock };
    defer conn.inbox.deinit(testing.allocator);
    const f = (try conn.next(testing.allocator, 2000)).?;
    try testing.expectEqual(wire.Kind.refused, f.kind);
    try d.finish(false);
}

const Session = @import("session.zig").Session;

/// The model's text has `needle` within ~5 s.
fn waitText(s: *Session, needle: []const u8) !void {
    var tries: u32 = 0;
    while (tries < 250) : (tries += 1) {
        const text = try s.copyText(testing.allocator);
        defer testing.allocator.free(text);
        if (std.mem.indexOf(u8, text, needle) != null) return;
        clock.sleepMs(20);
    }
    return error.TextNeverAppeared;
}

test "an app session through the daemon: detached, taken back with its screen, then closed" {
    testing.log_level = .err;
    var d: Running = .{ .server = undefined };
    try d.start("session");
    const keep: @import("session_child.zig").Daemon = .{ .socket = d.path, .id = "pane-s", .attach = false };
    {
        const s = try Session.open(testing.allocator, .{ .size = size, .shell = "/bin/sh", .daemon = keep });
        try s.write("echo first-$((3+4))\n");
        try waitText(s, "first-7");
        try testing.expect(s.foregroundGroup() == 0);
        // The daemon's shell is a real process: the app checks a typed `cadex claude` against it.
        try testing.expect(s.child.shellPid() > 0 and std.c.kill(s.child.shellPid(), @enumFromInt(0)) == 0);
        // The app quits: the shell goes on in the daemon.
        s.detach();
    }
    var back = keep;
    back.attach = true;
    const s = try Session.open(testing.allocator, .{ .size = size, .shell = "/bin/sh", .daemon = back });
    try waitText(s, "first-7");
    try s.write("echo second-$((4+4))\n");
    try waitText(s, "second-8");
    // A name the daemon does not know.
    var gone = keep;
    gone.id = "pane-gone";
    gone.attach = true;
    try testing.expectError(error.NotFound, Session.open(testing.allocator, .{ .size = size, .daemon = gone }));
    s.close();
    try d.finish(true);
}

test "SIGTERM's saved output comes back in a new session, once" {
    testing.log_level = .err;
    var d: Running = .{ .server = undefined };
    try d.start("saved");
    var dir_buf: [64]u8 = undefined;
    const dir = try std.fmt.bufPrint(&dir_buf, "/tmp/cadex-td-{d}-saved", .{c.getpid()});
    var dz: [65]u8 = @splat(0);
    @memcpy(dz[0..dir.len], dir);
    _ = c.mkdir(@ptrCast(&dz), 0o700);
    d.server.scrollback_dir = dir;
    var app = try client.Connection.connect(testing.allocator, d.path);
    defer app.deinit(testing.allocator);
    _ = try app.open(testing.allocator, "pane-t", size, "", "/bin/sh");
    try type_(&app, "echo before-$((5+5))\n");
    try waitOutput(&app, "before-10");
    d.server.saveAll();
    var path_buf: [128]u8 = undefined;
    const path = std.mem.span(@import("daemon_state.zig").savedPath(&path_buf, dir, "pane-t").?);
    const s = try Session.open(testing.allocator, .{ .size = size, .shell = "/bin/sh", .replay_path = path });
    defer s.close();
    try waitText(s, "before-10");
    try testing.expect(!@import("../../shared/fs.zig").exists(path));
    _ = c.rmdir(@ptrCast(&dz));
    try d.finish(false);
}

test "the app's check of the socket, or a refused attach, does not make the daemon leave" {
    var d: Running = .{ .server = undefined };
    try d.start("check");
    // The app's check: connect and close, no hello.
    _ = c.close(wire.connect(d.path).?);
    clock.sleepMs(300);
    {
        // Taking back a session the daemon lost, then opening a new one.
        var probe = try client.Connection.connect(testing.allocator, d.path);
        defer probe.deinit(testing.allocator);
        try testing.expectError(error.Refused, probe.attach(testing.allocator, "gone"));
    }
    clock.sleepMs(300);
    var app = try client.Connection.connect(testing.allocator, d.path);
    defer app.deinit(testing.allocator);
    const ready = try app.open(testing.allocator, "pane-c", size, "", "/bin/sh");
    try testing.expect(ready.alive);
    try app.close(testing.allocator);
    try d.finish(false);
}

test "frames sent just before the end of the connection are still answered" {
    var d: Running = .{ .server = undefined };
    try d.start("end");
    defer d.finish(false) catch {};
    var pair: [2]c_int = undefined;
    try testing.expect(socketpair(c.AF.UNIX, c.SOCK.STREAM, 0, &pair) == 0);
    defer _ = c.close(pair[0]);
    // Hello and a list, then the end, all waiting before the daemon reads:
    // as a pane's close and its connection's end arrive.
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);
    try wire.frame(testing.allocator, &out, .hello, &.{ wire.version, 0 });
    try wire.frame(testing.allocator, &out, .list, "");
    try wire.writeAll(pair[0], out.items);
    _ = c.shutdown(pair[0], 1);
    const state = @import("daemon_state.zig");
    var one: state.Client = .{ .fd = pair[1] };
    defer {
        one.inbox.deinit(testing.allocator);
        one.outbox.deinit(testing.allocator);
        _ = c.close(pair[1]);
    }
    wire.setNonblocking(pair[1]);
    try testing.expect(!@import("daemon_handle.zig").readClient(&d.server, &one));
    // Answered (hello_ok, sessions) although the connection had ended.
    var inbox: wire.Inbox = .{ .bytes = one.outbox };
    try testing.expectEqual(wire.Kind.hello_ok, (try inbox.next()).?.kind);
    try testing.expectEqual(wire.Kind.sessions, (try inbox.next()).?.kind);
}

extern "c" fn socketpair(domain: c_uint, kind: c_uint, protocol: c_uint, fds: *[2]c_int) c_int;
