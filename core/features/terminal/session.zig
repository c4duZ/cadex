//! A session: one shell on one pty, its terminal model, and the thread that
//! reads the shell's output into the model.

const std = @import("std");
const sync = @import("../../shared/sync.zig");
const Model = @import("model.zig").Model;
const pty = @import("pty.zig");
const render = @import("render.zig");
const input = @import("input.zig");
const selection = @import("selection.zig");
const paste_encoding = @import("paste.zig");
const local_url = @import("local_url.zig");

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
    /// A local server's address showed up in the output (local_url.zig),
    /// NUL-terminated, valid during the call. Once per address.
    on_local_url: ?*const fn (context: ?*anyopaque, url: [*:0]const u8) callconv(.c) void = null,
};

pub const Options = struct {
    size: Size,
    cwd: ?[]const u8 = null,
    /// Configured shell; empty or null falls back to $SHELL, then zsh.
    shell: ?[]const u8 = null,
    /// Lines of history to keep; 0 is the default (model.zig).
    history_lines: u32 = 0,
    callbacks: Callbacks = .{},
};

const read_buffer_size = 64 * 1024;

pub const Session = struct {
    gpa: std.mem.Allocator,
    model: *Model,
    child: pty.Child,
    callbacks: Callbacks,
    mutex: sync.Mutex = .{},
    reader: std.Thread = undefined,
    stop: std.atomic.Value(bool) = .init(false),
    /// Set by the reader once it collected the shell's exit status.
    reaped: bool = false,
    /// Only used from the thread that draws (the app main thread).
    renderer: render.Renderer = .{},
    /// Only used by the reader thread.
    local_urls: local_url.Detector = undefined,

    pub fn open(gpa: std.mem.Allocator, options: Options) !*Session {
        const self = try gpa.create(Session);
        errdefer gpa.destroy(self);

        const history: usize = if (options.history_lines == 0) @import("model.zig").scrollback_lines else options.history_lines;
        const model = try Model.createWithHistory(Model.defaultIo(), gpa, .{
            .cols = options.size.cols,
            .rows = options.size.rows,
        }, history);
        errdefer model.destroy();

        self.* = .{
            .gpa = gpa,
            .model = model,
            .child = try pty.Child.start(gpa, .{ .size = options.size, .cwd = options.cwd, .shell = options.shell }),
            .callbacks = options.callbacks,
            .local_urls = .{ .gpa = gpa },
        };
        errdefer self.child.kill();

        model.setReply(&replyToShell, self);
        model.setNotice(&forwardNotice);
        self.reader = try std.Thread.spawn(.{}, readLoop, .{self});
        return self;
    }

    /// Ends the shell, stops the reader and frees everything. No callback
    /// runs after this returns.
    pub fn close(self: *Session) void {
        self.stop.store(true, .release);
        self.child.unblockReader();
        self.reader.join();
        self.child.finish(self.reaped);
        self.renderer.deinit(self.gpa);
        self.local_urls.deinit();
        self.model.destroy();
        self.gpa.destroy(self);
    }

    /// Sends input (typed keys, pasted text) to the shell.
    pub fn write(self: *Session, bytes: []const u8) !void {
        self.lock();
        self.returnToInput();
        self.unlock();
        try self.child.write(bytes);
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
        try self.child.write(bytes);
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
        try self.child.resize(size);
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
        return !self.reaped and self.child.hasForegroundProcess();
    }

    /// The foreground program's process group, 0 for none (the shell).
    pub fn foregroundGroup(self: *Session) i32 {
        return if (self.reaped) 0 else self.child.foregroundGroup();
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
        self.mutex.lock();
    }

    pub fn unlock(self: *Session) void {
        self.mutex.unlock();
    }

    fn readLoop(self: *Session) void {
        var buf: [read_buffer_size]u8 = undefined;
        while (self.child.read(&buf, &self.stop)) |n| {
            self.lock();
            self.model.feed(buf[0..n]);
            self.unlock();
            if (self.callbacks.on_output) |notify| notify(self.callbacks.context);
            if (self.callbacks.on_local_url != null) self.local_urls.scan(buf[0..n], self, reportLocalUrl);
        }
        if (self.stop.load(.acquire)) return;

        const code = self.child.waitExitCode();
        self.reaped = true;
        if (self.callbacks.on_exit) |notify| notify(self.callbacks.context, code);
    }

    fn reportLocalUrl(self: *Session, url: []const u8) void {
        var z: [local_url.max_url + 40]u8 = undefined;
        if (url.len >= z.len) return;
        @memcpy(z[0..url.len], url);
        z[url.len] = 0;
        if (self.callbacks.on_local_url) |notify| notify(self.callbacks.context, z[0..url.len :0]);
    }

    fn forwardNotice(context: ?*anyopaque, notice: @import("model.zig").Notice) void {
        const self: *Session = @ptrCast(@alignCast(context.?));
        const callback = switch (notice) {
            .title => self.callbacks.on_title,
            .bell => self.callbacks.on_bell,
        };
        if (callback) |notify| notify(self.callbacks.context);
    }

    pub fn setCursorDefaults(self: *Session, shape: Model.CursorShape, blink: bool) void {
        self.lock();
        defer self.unlock();
        self.model.setCursorDefaults(shape, blink);
    }

    /// The theme's colors for this terminal (model.zig:setColors).
    pub fn setColors(self: *Session, colors: @import("model.zig").Colors) !void {
        self.lock();
        defer self.unlock();
        try self.model.setColors(colors);
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
        self.child.write(bytes) catch {};
    }
};
