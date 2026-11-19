//! A session's program kept by the terminal daemon (plan 19 phase E2,
//! docs/adr/0022-terminal-daemon.md): the same methods as pty.Child, so
//! session.zig runs on either. The output (the replay first, on attach)
//! comes as frames on the session's own connection; writing, resizing and
//! the foreground program go straight to the pty's master the daemon
//! handed over. Closing either ends the program (close) or lets it run in
//! the daemon (detach: the app quits, the window that saves goes away).

const std = @import("std");
const c = std.c;
const pty = @import("pty.zig");
const client = @import("daemon_client.zig");
const wire = @import("daemon_wire.zig");

pub const Start = struct {
    socket: []const u8,
    /// The app's name for the session (a pane's), unique in the daemon.
    id: []const u8,
    /// Take an existing session back (error.NotFound when the daemon has
    /// none by that name) instead of opening a new one.
    attach: bool,
    size: pty.Size,
    cwd: ?[]const u8 = null,
    shell: ?[]const u8 = null,
};

pub const Child = struct {
    gpa: std.mem.Allocator,
    conn: client.Connection,
    /// The master and the program's pid, for pty.Child's own methods.
    pty: pty.Child,
    exit_code: ?i32 = null,
    /// finish() leaves the program running in the daemon.
    detach: bool = false,
    /// How many others watch this session (plan 39 A: the phone), from the
    /// daemon's guests frame; read off the reader thread.
    guests: std.atomic.Value(u8) = .init(0),

    pub fn start(gpa: std.mem.Allocator, options: Start) !Child {
        var conn = client.Connection.connect(gpa, options.socket) catch |err| return switch (err) {
            error.NoDaemon, error.Version => error.NoDaemon,
            else => err,
        };
        errdefer conn.deinit(gpa);
        const ready = if (options.attach)
            conn.attach(gpa, options.id) catch |err| return if (err == error.Refused) error.NotFound else err
        else
            try conn.open(gpa, options.id, options.size, options.cwd orelse "", options.shell orelse "");
        var self: Child = .{ .gpa = gpa, .conn = conn, .pty = .{ .fd = conn.master orelse -1, .pid = ready.pid } };
        if (!ready.alive) self.exit_code = ready.exit_code;
        // Taken back: two size changes so a TUI draws itself again (the
        // replay alone may have lost its screen), the last one the app's.
        if (options.attach and ready.alive and self.pty.fd >= 0) {
            var smaller = options.size;
            smaller.rows -|= 1;
            self.resize(smaller) catch {};
            self.resize(options.size) catch {};
        }
        return self;
    }

    /// The next output frame's bytes into `buf` (at least wire.chunk), 0
    /// when the count of other screens changed, or null once the program ended, the daemon went away or `stop` turned true.
    pub fn read(self: *Child, buf: []u8, stop: *const std.atomic.Value(bool)) ?usize {
        std.debug.assert(buf.len >= wire.chunk);
        while (!stop.load(.acquire)) {
            const f = (self.conn.next(self.gpa, 50) catch {
                if (self.exit_code == null) self.exit_code = -1;
                return null;
            }) orelse continue;
            switch (f.kind) {
                .output => {
                    @memcpy(buf[0..f.payload.len], f.payload);
                    return f.payload.len;
                },
                .guests => {
                    var r: wire.Reader = .{ .rest = f.payload };
                    self.guests.store(r.int(u8) catch 0, .release);
                    // 0 bytes: the session tells the app (output never
                    // comes empty).
                    return 0;
                },
                .exited => {
                    var r: wire.Reader = .{ .rest = f.payload };
                    self.exit_code = r.int(i32) catch -1;
                    return null;
                },
                else => {},
            }
        }
        return null;
    }

    pub fn write(self: *Child, bytes: []const u8) error{WriteFailed}!void {
        if (self.pty.fd < 0) return error.WriteFailed;
        return self.pty.write(bytes);
    }

    /// Through the daemon when it shares the session with other screens
    /// (it sets the smallest); straight on the pty with one from before.
    pub fn resize(self: *Child, size: pty.Size) error{ResizeFailed}!void {
        if (self.pty.fd < 0) return;
        if (self.conn.revision < 2) return self.pty.resize(size);
        self.conn.resize(self.gpa, size) catch return error.ResizeFailed;
    }

    pub fn hasForegroundProcess(self: *Child) bool {
        return self.pty.fd >= 0 and self.pty.hasForegroundProcess();
    }

    pub fn foregroundGroup(self: *Child) i32 {
        return if (self.pty.fd >= 0) self.pty.foregroundGroup() else 0;
    }

    pub fn currentDirectory(self: *Child, buf: *pty.DirectoryBuffer) ?[]const u8 {
        return if (self.pty.fd >= 0) self.pty.currentDirectory(buf) else null;
    }

    pub fn waitExitCode(self: *Child) i32 {
        return self.exit_code orelse -1;
    }

    /// Nothing to do: the reader polls `stop` every 50 ms.
    pub fn unblockReader(self: *Child) void {
        _ = self;
    }

    /// After the reader stopped: ends the program in the daemon unless
    /// detaching, and lets go of the connection and the master.
    pub fn finish(self: *Child, reaped: bool) void {
        if (!self.detach and !reaped) self.conn.close(self.gpa) catch {};
        self.conn.deinit(self.gpa);
    }

    pub fn kill(self: *Child) void {
        self.conn.close(self.gpa) catch {};
        self.conn.deinit(self.gpa);
    }
};
