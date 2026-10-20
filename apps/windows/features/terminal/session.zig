//! A terminal session of the app: the core's cadex_terminal, its
//! preferences, and the notices of its reader thread (output, exit, title,
//! bell, a local server's address), handed to whoever holds the view
//! through `Events.post`, which must only queue them (PostMessage): the
//! window handles them on its own thread.

const std = @import("std");
const cadex = @import("cadex");

pub const Event = enum(u8) { output, exit, title, bell, local_url };

pub const Events = struct {
    context: *anyopaque,
    /// Called on the core's reader thread. Queue and return.
    post: *const fn (context: *anyopaque, session: *Session, event: Event) void,
};

pub const Preferences = struct {
    shell: []const u8 = "",
    history_lines: u32 = 10_000,
    /// CADEX_CURSOR_*.
    cursor: u8 = cadex.CADEX_CURSOR_BAR,
    cursor_blink: bool = false,
};

pub const Session = struct {
    gpa: std.mem.Allocator,
    terminal: *cadex.cadex_terminal,
    events: Events,
    /// Set by the reader thread with on_exit; read on the window's thread.
    exit_code: std.atomic.Value(i32) = .init(std.math.minInt(i32)),
    /// Coalesces output notices: one queued redraw at a time.
    output_queued: std.atomic.Value(bool) = .init(false),
    /// The last local server seen (http://localhost:5173/), for the preview offer.
    /// A spin lock: held only to copy 256 bytes (std.Thread.Mutex moved to std.Io in Zig 0.16).
    local_url_lock: std.atomic.Mutex = .unlocked,
    local_url: [256]u8 = undefined,
    local_url_len: usize = 0,

    pub const Error = error{ OpenFailed, OutOfMemory };

    /// Starts the shell in `cwd` (null: the user's folder) with `cols` x `rows`.
    pub fn open(gpa: std.mem.Allocator, cwd: ?[]const u8, cols: u16, rows: u16, prefs: Preferences, events: Events) Error!*Session {
        const self = try gpa.create(Session);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .terminal = undefined, .events = events };
        const cwd_z = if (cwd) |d| try gpa.dupeZ(u8, d) else null;
        defer if (cwd_z) |z| gpa.free(z);
        const shell_z = try gpa.dupeZ(u8, prefs.shell);
        defer gpa.free(shell_z);
        const options: cadex.cadex_terminal_options = .{
            .cols = @max(cols, 2),
            .rows = @max(rows, 1),
            .cwd = if (cwd_z) |z| z.ptr else null,
            .shell = shell_z.ptr,
            .context = self,
            .on_output = onOutput,
            .on_exit = onExit,
            .on_title = onTitle,
            .on_bell = onBell,
            .history_lines = prefs.history_lines,
            .on_local_url = onLocalUrl,
        };
        var terminal: ?*cadex.cadex_terminal = null;
        if (cadex.cadex_terminal_open(&options, &terminal) != cadex.CADEX_OK) return error.OpenFailed;
        self.terminal = terminal.?;
        _ = cadex.cadex_terminal_set_cursor(self.terminal, prefs.cursor, prefs.cursor_blink);
        return self;
    }

    /// Ends the shell; no notice comes after this returns.
    pub fn close(self: *Session) void {
        cadex.cadex_terminal_close(self.terminal);
        self.gpa.destroy(self);
    }

    fn of(context: ?*anyopaque) *Session {
        return @ptrCast(@alignCast(context.?));
    }

    fn onOutput(context: ?*anyopaque) callconv(.c) void {
        const self = of(context);
        if (self.output_queued.swap(true, .acq_rel)) return;
        self.events.post(self.events.context, self, .output);
    }

    fn onExit(context: ?*anyopaque, code: i32) callconv(.c) void {
        const self = of(context);
        self.exit_code.store(code, .release);
        self.events.post(self.events.context, self, .exit);
    }

    fn onTitle(context: ?*anyopaque) callconv(.c) void {
        const self = of(context);
        self.events.post(self.events.context, self, .title);
    }

    fn onBell(context: ?*anyopaque) callconv(.c) void {
        const self = of(context);
        self.events.post(self.events.context, self, .bell);
    }

    fn onLocalUrl(context: ?*anyopaque, url: [*c]const u8) callconv(.c) void {
        const self = of(context);
        const text = std.mem.span(url);
        lock(&self.local_url_lock);
        const n = @min(text.len, self.local_url.len);
        @memcpy(self.local_url[0..n], text[0..n]);
        self.local_url_len = n;
        self.local_url_lock.unlock();
        self.events.post(self.events.context, self, .local_url);
    }

    /// The window drew the output it was told about; the next output notifies again.
    pub fn drew(self: *Session) void {
        self.output_queued.store(false, .release);
    }

    /// The exit code once the shell ended on its own, else null.
    pub fn exitCode(self: *Session) ?i32 {
        const code = self.exit_code.load(.acquire);
        return if (code == std.math.minInt(i32)) null else code;
    }

    /// The local server's address, copied into `out`.
    pub fn localUrl(self: *Session, out: []u8) []const u8 {
        lock(&self.local_url_lock);
        defer self.local_url_lock.unlock();
        const n = @min(self.local_url_len, out.len);
        @memcpy(out[0..n], self.local_url[0..n]);
        return out[0..n];
    }

    pub fn write(self: *Session, bytes: []const u8) void {
        _ = cadex.cadex_terminal_write(self.terminal, bytes.ptr, bytes.len);
    }

    pub fn key(self: *Session, k: u16, mods: u8, text: []const u8, unshifted: u32) void {
        _ = cadex.cadex_terminal_key(self.terminal, k, mods, text.ptr, text.len, unshifted);
    }

    pub fn hasForegroundProcess(self: *Session) bool {
        return cadex.cadex_terminal_has_foreground_process(self.terminal);
    }

    /// A copy the caller frees with cadex_free, through `owned`.
    pub fn title(self: *Session) ?Owned {
        return copy(self.terminal, cadex.cadex_terminal_copy_title);
    }

    pub fn workingDirectory(self: *Session) ?Owned {
        return copy(self.terminal, cadex.cadex_terminal_copy_working_directory);
    }

    pub fn setColors(self: *Session, colors: cadex.cadex_terminal_colors) void {
        _ = cadex.cadex_terminal_set_colors(self.terminal, &colors);
    }

    pub fn setCursor(self: *Session, shape: u8, blink: bool) void {
        _ = cadex.cadex_terminal_set_cursor(self.terminal, shape, blink);
    }
};

fn lock(m: *std.atomic.Mutex) void {
    while (!m.tryLock()) std.atomic.spinLoopHint();
}

/// Bytes the core allocated; free once.
pub const Owned = struct {
    bytes: []const u8,

    pub fn free(self: Owned) void {
        cadex.cadex_free(@constCast(self.bytes.ptr));
    }
};

fn copy(terminal: *cadex.cadex_terminal, comptime f: anytype) ?Owned {
    var out: [*c]u8 = null;
    var len: usize = 0;
    if (f(terminal, &out, &len) != cadex.CADEX_OK or out == null) return null;
    return .{ .bytes = out[0..len] };
}

test {
    @import("win32").refAllDeep(@This());
}
