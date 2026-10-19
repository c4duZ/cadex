//! A session: one shell on one pty, its terminal model, and the thread that
//! reads the shell's output into the model.

const std = @import("std");
const c = std.c;
const Model = @import("model.zig").Model;
const pty = @import("pty.zig");
const shell_env = @import("shell_env.zig");
const render = @import("render.zig");
const input = @import("input.zig");
const selection = @import("selection.zig");
const paste_encoding = @import("paste.zig");

pub const Size = pty.Size;
pub const Frame = render.Frame;
pub const Pointer = selection.Pointer;
pub const Autoscroll = selection.Autoscroll;

/// Called on the reader thread. They must return quickly and must not call
/// close() on the same session: close() waits for the reader thread.
pub const Callbacks = struct {
    context: ?*anyopaque = null,
    /// New output is in the model; schedule a redraw.
    on_output: ?*const fn (context: ?*anyopaque) callconv(.c) void = null,
    /// The shell exited on its own. Exit code, or 128 + signal number.
    on_exit: ?*const fn (context: ?*anyopaque, exit_code: i32) callconv(.c) void = null,
    /// The title changed (OSC 0/2): read it with title().
    on_title: ?*const fn (context: ?*anyopaque) callconv(.c) void = null,
    /// The program rang the bell.
    on_bell: ?*const fn (context: ?*anyopaque) callconv(.c) void = null,
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
        errdefer pty.killNow(self.child);

        model.setReply(&replyToShell, self);
        model.setNotice(&forwardNotice);
        self.reader = try std.Thread.spawn(.{}, readLoop, .{self});
        return self;
    }

    /// Ends the shell (SIGHUP, then SIGKILL after a grace period), stops the
    /// reader and frees everything. No callback runs after this returns.
    pub fn close(self: *Session) void {
        self.stop.store(true, .release);
        self.reader.join();
        // Close our side of the pty before waiting for the shell. With the
        // reader stopped nobody drains its output, and an exiting shell
        // waits in the kernel for that drain: the app hung forever in
        // waitpid closing a tab that ran `sleep 100` (2026-10-19, sample of
        // the main thread in __wait4, zsh in state E).
        _ = c.close(self.child.fd);
        if (!self.reaped) pty.hangUp(self.child, hangup_grace_ms);
        self.renderer.deinit(self.gpa);
        self.model.destroy();
        self.gpa.destroy(self);
    }

    /// Sends input (typed keys, pasted text) to the shell.
    pub fn write(self: *Session, bytes: []const u8) !void {
        self.lock();
        self.returnToInput();
        self.unlock();
        try pty.writeAll(self.child.fd, bytes);
    }

    /// Sends a key press, encoded for the modes the program set (see
    /// input.zig). Keys that encode to nothing are dropped.
    pub fn key(self: *Session, k: input.Key, mods: input.Mods, text: []const u8, unshifted: u21) !void {
        var buf: [input.max_sequence_len]u8 = undefined;
        self.lock();
        const encoded = input.encodeKey(&buf, &self.model.terminal, k, mods, text, unshifted);
        self.returnToInput();
        self.unlock();
        const bytes = try encoded;
        if (bytes.len > 0) try self.write(bytes);
    }

    /// Pastes text, encoded for the program (bracketed paste, see paste.zig).
    pub fn paste(self: *Session, text: []const u8) !void {
        self.lock();
        const encoded = paste_encoding.encode(self.gpa, &self.model.terminal, text);
        self.returnToInput();
        self.unlock();
        const bytes = try encoded;
        defer self.gpa.free(bytes);
        try pty.writeAll(self.child.fd, bytes);
    }

    /// False when the paste could run commands unseen (paste.zig:isSafe).
    pub fn isPasteSafe(self: *Session, text: []const u8) bool {
        self.lock();
        defer self.unlock();
        return paste_encoding.isSafe(&self.model.terminal, text);
    }

    /// Typing or pasting goes back to the prompt: drops the selection and
    /// scrolls to the bottom (docs/spec/terminal.md). Hold the lock.
    fn returnToInput(self: *Session) void {
        selection.clear(&self.model.terminal);
        self.model.scrollToBottom();
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
        const captured = self.renderer.capture(self.gpa, &self.model.terminal, &self.model.search);
        self.unlock();
        try captured;
        return self.renderer.build(self.gpa, &self.model.search);
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

        const code = pty.waitExitCode(self.child.pid);
        self.reaped = true;
        if (self.callbacks.on_exit) |notify| notify(self.callbacks.context, code);
    }

    fn forwardNotice(context: ?*anyopaque, notice: @import("model.zig").Notice) void {
        const self: *Session = @ptrCast(@alignCast(context.?));
        const callback = switch (notice) {
            .title => self.callbacks.on_title,
            .bell => self.callbacks.on_bell,
        };
        if (callback) |notify| notify(self.callbacks.context);
    }

    /// The title the program set (OSC 0/2), empty if none. Caller frees.
    pub fn title(self: *Session, gpa: std.mem.Allocator) ![]u8 {
        self.lock();
        defer self.unlock();
        return gpa.dupe(u8, self.model.title() orelse "");
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
