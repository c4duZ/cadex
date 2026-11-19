//! The terminal daemon (docs/adr/0022-terminal-daemon.md, plan 19 phase E1):
//! a process apart from the app that owns the ptys, so closing or crashing
//! the app leaves the shells and agents running. It keeps each session's
//! raw output (`daemon_ring.zig`) and modes (`daemon_modes.zig`), hands the
//! app the pty's master and forwards new output (`daemon_wire.zig`). No
//! terminal model and no libghostty: the app replays the bytes into its own.
//! One thread, one poll; nothing wakes it while nothing happens. It leaves
//! by itself once it has no session and no app connected.

const std = @import("std");
const c = std.c;
const clock = @import("../../shared/clock.zig");
const wire = @import("daemon_wire.zig");
const state = @import("daemon_state.zig");
const handle = @import("daemon_handle.zig");
const guests = @import("daemon_guests.zig");
const Session = state.Session;
const Client = state.Client;

/// SIGHUP first, SIGKILL this long after, as a tab closing does
/// (pty_posix.zig: hangup_grace_ms).
pub const hangup_grace_ms = 200;
/// Started and no app said hello in this time: the app that started it is
/// gone, and the daemon leaves.
pub const startup_grace_ms = 10_000;
/// With no session and no app, it leaves after this long: an app checking
/// the socket, or taking a gone session back and then opening a new one,
/// connects again within it (found 2026-11-15: the app's check alone made
/// the daemon leave before the app's session came).
pub const linger_ms = 3_000;

pub const Server = struct {
    gpa: std.mem.Allocator,
    listener: c_int,
    sessions: std.ArrayList(*Session) = .empty,
    clients: std.ArrayList(*Client) = .empty,
    started_ms: i64,
    /// An app said hello (a bare connect, the app's check, does not count).
    ever_connected: bool = false,
    /// Since when it has had no session and no app.
    empty_since: ?i64 = null,
    /// Tests stop the loop from another thread.
    stop: std.atomic.Value(bool) = .init(false),
    /// SIGCHLD writes a byte here (`childEnded`): an ended program wakes
    /// the poll, with no timer.
    wake: [2]c_int = .{ -1, -1 },
    /// Where SIGTERM (the Mac shutting down) saves each session's output,
    /// `<id>.raw`, for the app to show in a new shell (scrollback-only
    /// restore, docs/adr/0022-terminal-daemon.md). Null: not saved.
    scrollback_dir: ?[]const u8 = null,

    /// Listens on `path` (its folder must exist). error.Running when a
    /// daemon already answers there; a dead one's socket file is replaced.
    pub fn listen(gpa: std.mem.Allocator, path: []const u8) !Server {
        if (wire.connect(path)) |fd| {
            _ = c.close(fd);
            return error.Running;
        }
        var addr = try wire.address(path);
        var path_z: [104]u8 = @splat(0);
        @memcpy(path_z[0..path.len], path);
        _ = c.unlink(@ptrCast(&path_z));
        const fd = c.socket(c.AF.UNIX, c.SOCK.STREAM, 0);
        if (fd < 0) return error.SocketFailed;
        errdefer _ = c.close(fd);
        if (c.bind(fd, @ptrCast(&addr), @sizeOf(c.sockaddr.un)) != 0) return error.BindFailed;
        _ = c.chmod(@ptrCast(&path_z), 0o600);
        if (c.listen(fd, 16) != 0) return error.ListenFailed;
        wire.setNonblocking(fd);
        wire.setCloexec(fd);
        var wake: [2]c_int = undefined;
        if (c.pipe(&wake) != 0) return error.PipeFailed;
        for (wake) |end| {
            wire.setNonblocking(end);
            wire.setCloexec(end);
        }
        wake_fd.store(wake[1], .release);
        _ = signal(sigchld, &childEnded);
        _ = signal(sigterm, &terminated);
        return .{ .gpa = gpa, .listener = fd, .started_ms = clock.monotonicMs(), .wake = wake };
    }

    pub fn deinit(self: *Server) void {
        for (self.clients.items) |client| client.destroy(self.gpa);
        self.clients.deinit(self.gpa);
        for (self.sessions.items) |s| {
            if (s.alive()) _ = c.kill(s.pid, .KILL);
            _ = c.waitpid(s.pid, null, 0);
            s.destroy(self.gpa);
        }
        self.sessions.deinit(self.gpa);
        _ = c.close(self.listener);
        _ = signal(sigchld, null);
        _ = signal(sigterm, null);
        wake_fd.store(-1, .release);
        for (self.wake) |end| _ = c.close(end);
    }

    /// From another thread: the loop ends at its next turn (the wake pipe
    /// gets it out of poll).
    pub fn requestStop(self: *Server) void {
        self.stop.store(true, .release);
        _ = c.write(self.wake[1], "s", 1);
    }

    /// Runs until there is no session and no app, or `stop`.
    pub fn run(self: *Server) !void {
        var fds: std.ArrayList(c.pollfd) = .empty;
        defer fds.deinit(self.gpa);
        while (!self.stop.load(.acquire)) {
            self.reap();
            if (self.idle()) return;
            fds.clearRetainingCapacity();
            try fds.append(self.gpa, .{ .fd = self.listener, .events = c.POLL.IN, .revents = 0 });
            try fds.append(self.gpa, .{ .fd = self.wake[0], .events = c.POLL.IN, .revents = 0 });
            for (self.clients.items) |client| {
                const out: i16 = if (client.pending() > 0) c.POLL.OUT else 0;
                try fds.append(self.gpa, .{ .fd = client.fd, .events = c.POLL.IN | out, .revents = 0 });
            }
            for (self.sessions.items) |s| {
                const held = s.client != null and s.client.?.pending() > state.backlog_limit;
                const events: i16 = if (s.master >= 0 and !held) c.POLL.IN else 0;
                try fds.append(self.gpa, .{ .fd = s.master, .events = events, .revents = 0 });
            }
            const got = c.poll(fds.items.ptr, @intCast(fds.items.len), self.timeoutMs());
            if (got < 0) continue;
            try self.serve(fds.items);
        }
    }

    fn serve(self: *Server, fds: []const c.pollfd) !void {
        const n_clients = self.clients.items.len;
        const n_sessions = self.sessions.items.len;
        // Sessions first: their output goes to the outboxes the clients flush.
        var i: usize = n_sessions;
        while (i > 0) {
            i -= 1;
            const revents = fds[2 + n_clients + i].revents;
            if (revents != 0) self.readSession(self.sessions.items[i]);
        }
        i = n_clients;
        while (i > 0) {
            i -= 1;
            const client = self.clients.items[i];
            const revents = fds[2 + i].revents;
            var alive = true;
            if (revents & (c.POLL.IN | c.POLL.HUP | c.POLL.ERR) != 0) alive = handle.readClient(self, client);
            if (alive) alive = client.flush(self.gpa) and !(client.closing and client.pending() == 0);
            if (!alive) self.drop(i);
        }
        if (fds[1].revents & c.POLL.IN != 0) {
            var buf: [64]u8 = undefined;
            while (true) {
                const n = c.read(self.wake[0], &buf, buf.len);
                if (n <= 0) break;
                if (std.mem.indexOfScalar(u8, buf[0..@intCast(n)], 't') != null) {
                    self.saveAll();
                    self.stop.store(true, .release);
                }
            }
        }
        if (fds[0].revents & c.POLL.IN != 0) self.accept();
    }

    fn accept(self: *Server) void {
        while (true) {
            const fd = c.accept(self.listener, null, null);
            if (fd < 0) return;
            if (!wire.sameUser(fd)) {
                _ = c.close(fd);
                continue;
            }
            wire.setNonblocking(fd);
            wire.setCloexec(fd);
            wire.noSigpipe(fd);
            const client = self.gpa.create(Client) catch {
                _ = c.close(fd);
                return;
            };
            client.* = .{ .fd = fd };
            self.clients.append(self.gpa, client) catch {
                client.destroy(self.gpa);
                return;
            };
        }
    }

    /// The app let go: its session keeps running, unless it already ended
    /// and the app was told.
    fn drop(self: *Server, index: usize) void {
        const client = self.clients.swapRemove(index);
        if (client.guest) guests.leave(self, client) else if (client.session) |s| self.release(s);
        client.destroy(self.gpa);
    }

    /// The app let go of `s`: gone if it ended and the app was told, else
    /// the pty takes the guests' size until an app takes it back.
    pub fn release(self: *Server, s: *Session) void {
        s.client = null;
        if (!s.alive() and s.exit_told) self.remove(s) else guests.apply(s);
    }

    pub fn remove(self: *Server, s: *Session) void {
        for (self.sessions.items, 0..) |item, i| if (item == s) {
            _ = self.sessions.swapRemove(i);
            break;
        };
        guests.detachAll(s);
        s.destroy(self.gpa);
    }

    pub fn find(self: *Server, id: []const u8) ?*Session {
        for (self.sessions.items) |s| if (std.mem.eql(u8, s.id, id)) return s;
        return null;
    }

    fn readSession(self: *Server, s: *Session) void {
        var buf: [wire.chunk]u8 = undefined;
        const n = c.read(s.master, &buf, buf.len);
        if (n < 0 and (c.errno(n) == .INTR or c.errno(n) == .AGAIN)) return;
        if (n <= 0) {
            // 0 or EIO: every holder of the pty's other side closed it.
            _ = c.close(s.master);
            s.master = -1;
            return;
        }
        self.keep(s, buf[0..@intCast(n)]);
    }

    fn keep(self: *Server, s: *Session, bytes: []const u8) void {
        s.ring.append(self.gpa, bytes) catch {};
        s.modes.feed(bytes);
        if (s.client) |client| client.sendOutput(self.gpa, bytes) catch {};
        guests.fanOut(self, s, bytes);
    }

    /// Collects ended programs: the last output, then "exited" to the app.
    fn reap(self: *Server) void {
        const now = clock.monotonicMs();
        var i: usize = self.sessions.items.len;
        while (i > 0) {
            i -= 1;
            const s = self.sessions.items[i];
            if (!s.alive()) continue;
            if (s.kill_at) |at| if (now >= at) {
                _ = c.kill(s.pid, .KILL);
            };
            var status: c_int = 0;
            if (c.waitpid(s.pid, &status, c.W.NOHANG) != s.pid) continue;
            s.exit_code = decodeStatus(status);
            self.drain(s);
            guests.tellExited(self, s);
            if (s.kill_at != null) {
                // Closed by the app: nobody waits for its end.
                self.remove(s);
                continue;
            }
            if (s.client) |client| {
                var p: wire.Payload = .{ .gpa = self.gpa };
                defer p.deinit();
                p.int(i32, s.exit_code.?) catch {};
                client.send(self.gpa, .exited, p.bytes.items) catch {};
                s.exit_told = true;
            }
        }
    }

    /// What the ended program left in the pty, then the master closes (a
    /// process it left behind may hold the pty open forever).
    fn drain(self: *Server, s: *Session) void {
        if (s.master < 0) return;
        var buf: [wire.chunk]u8 = undefined;
        while (true) {
            const n = c.read(s.master, &buf, buf.len);
            if (n <= 0) break;
            self.keep(s, buf[0..@intCast(n)]);
        }
        _ = c.close(s.master);
        s.master = -1;
    }

    /// Each running session's replay, for after the Mac restarts.
    pub fn saveAll(self: *Server) void {
        if (self.scrollback_dir) |dir| state.saveAll(self.gpa, self.sessions.items, dir);
    }

    fn idle(self: *Server) bool {
        if (self.sessions.items.len > 0 or self.clients.items.len > 0) {
            self.empty_since = null;
            return false;
        }
        const now = clock.monotonicMs();
        if (!self.ever_connected) return now - self.started_ms >= startup_grace_ms;
        const since = self.empty_since orelse now;
        self.empty_since = since;
        return now - since >= linger_ms;
    }

    /// Until the next thing that needs time: a kill or the startup grace.
    /// -1 (no wakeup) otherwise.
    fn timeoutMs(self: *const Server) i32 {
        const now = clock.monotonicMs();
        var next: ?i64 = null;
        if (!self.ever_connected and self.sessions.items.len == 0) next = self.started_ms + startup_grace_ms;
        if (self.empty_since) |since| next = since + linger_ms;
        for (self.sessions.items) |s| {
            if (!s.alive()) continue;
            if (s.kill_at) |t| next = if (next) |n| @min(n, t) else t;
        }
        // An ending program wakes the poll by SIGCHLD.
        const t = next orelse return -1;
        return @intCast(std.math.clamp(t - now, 0, std.math.maxInt(i32)));
    }
};

const sigchld: c_int = 20;
const sigterm: c_int = 15;
extern "c" fn signal(sig: c_int, handler: ?*const fn (c_int) callconv(.c) void) ?*const anyopaque;
var wake_fd: std.atomic.Value(c_int) = .init(-1);

/// SIGTERM: the loop saves the sessions' output and leaves.
fn terminated(_: c_int) callconv(.c) void {
    const fd = wake_fd.load(.acquire);
    if (fd >= 0) _ = c.write(fd, "t", 1);
}

/// SIGCHLD: only an async-signal-safe write, the loop does the rest.
fn childEnded(_: c_int) callconv(.c) void {
    const fd = wake_fd.load(.acquire);
    if (fd >= 0) _ = c.write(fd, "x", 1);
}

/// Exit code, or 128 + signal, as shells write $?.
fn decodeStatus(status: c_int) i32 {
    const sig = status & 0x7f;
    if (sig == 0) return (status >> 8) & 0xff;
    return 128 + sig;
}

