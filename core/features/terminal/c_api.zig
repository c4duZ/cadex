//! The terminal feature's part of the C API (include/cadex.h). Thin: it
//! converts C types and errors and calls the Session.

const std = @import("std");
const status = @import("../../status.zig");
const terminal = @import("terminal.zig");
const Session = terminal.Session;

/// The core is called from Swift and allocates with malloc, so a buffer it
/// returns can be released with cadex_free (or free()).
const gpa = std.heap.c_allocator;

pub const Options = extern struct {
    cols: u16,
    rows: u16,
    cwd: ?[*:0]const u8,
    shell: ?[*:0]const u8,
    context: ?*anyopaque,
    on_output: ?*const fn (?*anyopaque) callconv(.c) void,
    on_exit: ?*const fn (?*anyopaque, i32) callconv(.c) void,
    on_title: ?*const fn (?*anyopaque) callconv(.c) void,
    on_bell: ?*const fn (?*anyopaque) callconv(.c) void,
    history_lines: u32,
    on_local_url: ?*const fn (?*anyopaque, [*:0]const u8) callconv(.c) void,
};

pub export fn cadex_terminal_open(options: ?*const Options, out: ?*?*Session) callconv(.c) status.Code {
    const o = options orelse return status.invalid_argument;
    const result = out orelse return status.invalid_argument;
    if (o.cols == 0 or o.rows == 0) return status.invalid_argument;

    result.* = Session.open(gpa, .{
        .size = .{ .cols = o.cols, .rows = o.rows },
        .cwd = if (o.cwd) |s| std.mem.span(s) else null,
        .shell = if (o.shell) |s| std.mem.span(s) else null,
        .history_lines = o.history_lines,
        .callbacks = .{
            .context = o.context,
            .on_output = o.on_output,
            .on_exit = o.on_exit,
            .on_title = o.on_title,
            .on_bell = o.on_bell,
            .on_local_url = o.on_local_url,
        },
    }) catch |err| return status.fromError(err);
    return status.ok;
}

pub export fn cadex_terminal_close(session: ?*Session) callconv(.c) void {
    if (session) |s| s.close();
}

pub export fn cadex_terminal_write(session: ?*Session, bytes: ?[*]const u8, len: usize) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    if (len == 0) return status.ok;
    const data = bytes orelse return status.invalid_argument;
    s.write(data[0..len]) catch |err| return status.fromError(err);
    return status.ok;
}

/// A key that is not plain text: special keys, and text with Ctrl or Alt.
/// Encoded by the core for the program's current modes (input.zig).
pub export fn cadex_terminal_key(
    session: ?*Session,
    key: u16,
    mods: u8,
    text: ?[*]const u8,
    text_len: usize,
    unshifted_codepoint: u32,
) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const typed: []const u8 = if (text_len == 0) "" else (text orelse return status.invalid_argument)[0..text_len];
    const unshifted = std.math.cast(u21, unshifted_codepoint) orelse return status.invalid_argument;
    s.key(@enumFromInt(key), @bitCast(mods), typed, unshifted) catch |err| return switch (err) {
        error.InvalidKey, error.KeyTooLong => status.invalid_argument,
        else => status.fromError(err),
    };
    return status.ok;
}

pub export fn cadex_terminal_resize(
    session: ?*Session,
    cols: u16,
    rows: u16,
    cell_width_px: u16,
    cell_height_px: u16,
) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    if (cols == 0 or rows == 0) return status.invalid_argument;
    s.resize(.{
        .cols = cols,
        .rows = rows,
        .cell_width_px = cell_width_px,
        .cell_height_px = cell_height_px,
    }) catch |err| return status.fromError(err);
    return status.ok;
}

pub export fn cadex_terminal_has_foreground_process(session: ?*Session) callconv(.c) bool {
    const s = session orelse return false;
    return s.hasForegroundProcess();
}

pub export fn cadex_terminal_foreground_group(session: ?*Session) callconv(.c) i32 {
    const s = session orelse return 0;
    return s.foregroundGroup();
}

/// Visible text, one line per row, not NUL-terminated. Free with cadex_free.
pub export fn cadex_terminal_copy_text(session: ?*Session, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const ptr = out orelse return status.invalid_argument;
    const len = out_len orelse return status.invalid_argument;
    const text = s.copyText(gpa) catch |err| return status.fromError(err);
    // A Zig empty slice owns no memory and its pointer is not from malloc:
    // hand out NULL so cadex_free never sees it.
    ptr.* = if (text.len == 0) null else @constCast(text.ptr);
    len.* = text.len;
    return status.ok;
}

/// The title the program set (OSC 0/2), not NUL-terminated. Free with
/// cadex_free. No title: *out is NULL and *out_len is 0.
pub export fn cadex_terminal_copy_title(session: ?*Session, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const ptr = out orelse return status.invalid_argument;
    const len = out_len orelse return status.invalid_argument;
    const text = s.title(gpa) catch |err| return status.fromError(err);
    ptr.* = if (text.len == 0) null else text.ptr;
    len.* = text.len;
    return status.ok;
}

/// The session's current directory (OSC 7, or the foreground program's),
/// not NUL-terminated. Free with cadex_free. Unknown: *out is NULL.
pub export fn cadex_terminal_copy_working_directory(session: ?*Session, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const ptr = out orelse return status.invalid_argument;
    const len = out_len orelse return status.invalid_argument;
    ptr.* = null;
    len.* = 0;
    var buffers: terminal.view.DirectoryBuffers = undefined;
    const dir = terminal.view.directory(s, &buffers) orelse return status.ok;
    if (dir.len == 0) return status.ok;
    const copy = gpa.dupe(u8, dir) catch return status.out_of_memory;
    ptr.* = copy.ptr;
    len.* = copy.len;
    return status.ok;
}

/// The cursor's default shape (CADEX_CURSOR_BLOCK, _BAR, _UNDERLINE) and
/// blinking. A shape the program set stays until it resets it.
pub export fn cadex_terminal_set_cursor(session: ?*Session, shape: u8, blink: bool) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const cursor = std.enums.fromInt(@import("model.zig").Model.CursorShape, shape) orelse return status.invalid_argument;
    s.setCursorDefaults(cursor, blink);
    return status.ok;
}

/// The theme's colors: background, text, cursor and the 16 ANSI colors
/// become the terminal's defaults (docs/spec/themes.md).
pub export fn cadex_terminal_set_colors(session: ?*Session, colors: ?*const @import("model.zig").Colors) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const c = colors orelse return status.invalid_argument;
    s.setColors(c.*) catch |err| return status.fromError(err);
    return status.ok;
}

/// Captures the screen into a flat frame for drawing. Call only from the
/// thread that draws; the frame stays valid until the next call or close.
pub export fn cadex_terminal_update_frame(session: ?*Session, out: ?*?*const terminal.Frame) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const frame = out orelse return status.invalid_argument;
    frame.* = s.updateFrame() catch |err| return status.fromError(err);
    return status.ok;
}

// ---- Paste ----

/// Pastes text, encoded for the program: bracketed paste when it asked for
/// it, newlines as Enter otherwise, control bytes as spaces.
pub export fn cadex_terminal_paste(session: ?*Session, bytes: ?[*]const u8, len: usize) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    if (len == 0) return status.ok;
    const data = bytes orelse return status.invalid_argument;
    s.paste(data[0..len]) catch |err| return status.fromError(err);
    return status.ok;
}

/// False when pasting could run commands unseen: several lines without
/// bracketed paste, or text that ends the bracketed frame early.
pub export fn cadex_terminal_paste_is_safe(session: ?*Session, bytes: ?[*]const u8, len: usize) callconv(.c) bool {
    const s = session orelse return false;
    if (len == 0) return true;
    const data = bytes orelse return false;
    return s.isPasteSafe(data[0..len]);
}

/// Paths (NUL-terminated UTF-8) escaped for the shell and joined by spaces,
/// not NUL-terminated. Free with cadex_free.
pub export fn cadex_terminal_quote_paths(
    paths: ?[*]const ?[*:0]const u8,
    count: usize,
    out: ?*?[*]u8,
    out_len: ?*usize,
) callconv(.c) status.Code {
    const ptr = out orelse return status.invalid_argument;
    const len = out_len orelse return status.invalid_argument;
    ptr.* = null;
    len.* = 0;
    if (count == 0) return status.ok;
    const list = paths orelse return status.invalid_argument;

    const slices = gpa.alloc([]const u8, count) catch return status.out_of_memory;
    defer gpa.free(slices);
    for (slices, 0..) |*slice, i| {
        slice.* = std.mem.span(list[i] orelse return status.invalid_argument);
    }
    const quoted = terminal.quotePaths(gpa, slices) catch |err| return status.fromError(err);
    // Never empty here (count > 0 adds at least the quotes), but keep the
    // rule: an empty Zig slice is not from malloc.
    if (quoted.len == 0) return status.ok;
    ptr.* = quoted.ptr;
    len.* = quoted.len;
    return status.ok;
}
