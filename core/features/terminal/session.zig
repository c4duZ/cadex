//! A session: one shell on one pty, its terminal model, and the thread that
//! reads the shell's output into the model.

const std = @import("std");
const c = std.c;
const Model = @import("model.zig").Model;
const pty = @import("pty.zig");
const shell_env = @import("shell_env.zig");
const render = @import("render.zig");

extern "c" fn usleep(microseconds: c_uint) c_int;

pub const Size = pty.Size;
pub const Frame = render.Frame;

/// Called on the reader thread. They must return quickly and must not call
/// close() on the same session: close() waits for the reader thread.
pub const Callbacks = struct {
    context: ?*anyopaque = null,
    /// New output is in the model; schedule a redraw.
    on_output: ?*const fn (context: ?*anyopaque) callconv(.c) void = null,
    /// The shell exited on its own. Exit code, or 128 + signal number.
    on_exit: ?*const fn (context: ?*anyopaque, exit_code: i32) callconv(.c) void = null,
};

pub const Options = struct {
    size: Size,
    cwd: ?[]const u8 = null,
    /// Configured shell; empty or null falls back to $SHELL, then zsh.
    shell: ?[]const u8 = null,
    callbacks: Callbacks = .{},
};

/// How often the reader wakes to check whether close() asked it to stop.
const stop_poll_ms = 50;
/// Grace period for the shell to exit on SIGHUP before it is killed.
const hangup_grace_ms = 200;
const read_buffer_size = 64 * 1024;

pub const Session = struct {
    gpa: std.mem.Allocator,
    model: *Model,
    child: pty.Child,
    callbacks: Callbacks,
    mutex: c.pthread_mutex_t = c.PTHREAD_MUTEX_INITIALIZER,
    reader: std.Thread = undefined,
    stop: std.atomic.Value(bool) = .init(false),
    /// Set by the reader once it collected the shell's exit status.
    reaped: bool = false,
    /// Only used from the thread that draws (the app main thread).
    renderer: render.Renderer = .{},

    pub fn open(gpa: std.mem.Allocator, options: Options) !*Session {
        const self = try gpa.create(Session);
        errdefer gpa.destroy(self);

        const model = try Model.create(Model.defaultIo(), gpa, .{
            .cols = options.size.cols,
            .rows = options.size.rows,
        });
        errdefer model.destroy();

        self.* = .{
            .gpa = gpa,
            .model = model,
            .child = try spawnShell(gpa, options),
            .callbacks = options.callbacks,
        };
        errdefer killNow(self.child);

        model.setReply(&replyToShell, self);
        self.reader = try std.Thread.spawn(.{}, readLoop, .{self});
        return self;
    }

    /// Ends the shell (SIGHUP, then SIGKILL after a grace period), stops the
    /// reader and frees everything. No callback runs after this returns.
    pub fn close(self: *Session) void {
        self.stop.store(true, .release);
        self.reader.join();
        if (!self.reaped) hangUp(self.child);
        _ = c.close(self.child.fd);
        self.renderer.deinit(self.gpa);
        self.model.destroy();
        self.gpa.destroy(self);
    }

    /// Sends input (typed keys, pasted text) to the shell.
    pub fn write(self: *Session, bytes: []const u8) !void {
        try pty.writeAll(self.child.fd, bytes);
    }

    pub fn resize(self: *Session, size: Size) !void {
        self.lock();
        defer self.unlock();
        try pty.resize(self.child.fd, size);
        try self.model.resize(.{ .cols = size.cols, .rows = size.rows });
    }

    /// Captures the screen into a flat frame for drawing. Call from one thread
    /// only (the one that draws); the frame is valid until the next call.
    pub fn updateFrame(self: *Session) !*const Frame {
        self.lock();
        const captured = self.renderer.capture(self.gpa, &self.model.terminal);
        self.unlock();
        try captured;
        return self.renderer.build(self.gpa);
    }

    pub fn hasForegroundProcess(self: *Session) bool {
        return !self.reaped and pty.hasForegroundProcess(self.child);
    }

    /// Visible text, one line per row. Caller frees with `gpa`.
    pub fn copyText(self: *Session, gpa: std.mem.Allocator) ![]const u8 {
        self.lock();
        defer self.unlock();
        return self.model.plainText(gpa);
    }

    /// The model is shared with the reader thread: hold the lock while
    /// reading it (for example, while drawing a frame).
    pub fn lock(self: *Session) void {
        _ = c.pthread_mutex_lock(&self.mutex);
    }

    pub fn unlock(self: *Session) void {
        _ = c.pthread_mutex_unlock(&self.mutex);
    }

    fn readLoop(self: *Session) void {
        var buf: [read_buffer_size]u8 = undefined;
        var fds = [_]c.pollfd{.{ .fd = self.child.fd, .events = c.POLL.IN, .revents = 0 }};
        while (!self.stop.load(.acquire)) {
            const ready = c.poll(&fds, 1, stop_poll_ms);
            if (ready <= 0) continue;
            const n = c.read(self.child.fd, &buf, buf.len);
            if (n < 0 and c.errno(n) == .INTR) continue;
            // 0 or EIO: the shell closed its side of the pty.
            if (n <= 0) break;

            self.lock();
            self.model.feed(buf[0..@intCast(n)]);
            self.unlock();
            if (self.callbacks.on_output) |notify| notify(self.callbacks.context);
        }
        if (self.stop.load(.acquire)) return;

        const code = waitExitCode(self.child.pid);
        self.reaped = true;
        if (self.callbacks.on_exit) |notify| notify(self.callbacks.context, code);
    }

    fn replyToShell(context: ?*anyopaque, bytes: []const u8) void {
        const self: *Session = @ptrCast(@alignCast(context.?));
        // A failed reply to a terminal query is not worth failing the
        // session for; the program just does not get its answer.
        pty.writeAll(self.child.fd, bytes) catch {};
    }
};

fn spawnShell(gpa: std.mem.Allocator, options: Options) !pty.Child {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    const env_shell = if (c.getenv("SHELL")) |s| std.mem.span(s) else null;
    const shell = try a.dupeZ(u8, shell_env.resolveShell(options.shell, env_shell));
    const cwd = if (options.cwd) |dir| (try a.dupeZ(u8, dir)).ptr else null;
    const argv = try shell_env.loginArgv(a, shell);
    const envp = try shell_env.sessionEnv(a, try parentEnv(a));
    return pty.spawn(shell.ptr, argv, envp, cwd, options.size);
}

fn parentEnv(arena: std.mem.Allocator) ![]const [*:0]const u8 {
    var list: std.ArrayList([*:0]const u8) = .empty;
    var i: usize = 0;
    while (c.environ[i]) |entry| : (i += 1) try list.append(arena, entry);
    return list.items;
}

fn waitExitCode(pid: c.pid_t) i32 {
    var status: c_int = 0;
    while (c.waitpid(pid, &status, 0) < 0) {
        if (c.errno(@as(c_int, -1)) != .INTR) return -1;
    }
    return decodeStatus(status);
}

/// Exit code for a normal exit, 128 + signal for a killed shell (the same
/// convention shells use for $?).
fn decodeStatus(status: c_int) i32 {
    const signal = status & 0x7f;
    if (signal == 0) return (status >> 8) & 0xff;
    return 128 + signal;
}

fn hangUp(child: pty.Child) void {
    _ = c.kill(child.pid, .HUP);
    var waited: u32 = 0;
    while (waited < hangup_grace_ms) : (waited += 10) {
        if (c.waitpid(child.pid, null, c.W.NOHANG) != 0) return;
        _ = usleep(10 * 1000);
    }
    killNow(child);
}

fn killNow(child: pty.Child) void {
    _ = c.kill(child.pid, .KILL);
    _ = c.waitpid(child.pid, null, 0);
}

test "exit status decoding follows the shell convention" {
    try std.testing.expectEqual(@as(i32, 0), decodeStatus(0));
    try std.testing.expectEqual(@as(i32, 3), decodeStatus(3 << 8));
    try std.testing.expectEqual(@as(i32, 128 + 9), decodeStatus(9));
}
