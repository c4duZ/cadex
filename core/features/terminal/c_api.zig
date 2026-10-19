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
};

pub export fn cadex_terminal_open(options: ?*const Options, out: ?*?*Session) callconv(.c) status.Code {
    const o = options orelse return status.invalid_argument;
    const result = out orelse return status.invalid_argument;
    if (o.cols == 0 or o.rows == 0) return status.invalid_argument;

    result.* = Session.open(gpa, .{
        .size = .{ .cols = o.cols, .rows = o.rows },
        .cwd = if (o.cwd) |s| std.mem.span(s) else null,
        .shell = if (o.shell) |s| std.mem.span(s) else null,
        .callbacks = .{ .context = o.context, .on_output = o.on_output, .on_exit = o.on_exit },
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

/// Captures the screen into a flat frame for drawing. Call only from the
/// thread that draws; the frame stays valid until the next call or close.
pub export fn cadex_terminal_update_frame(session: ?*Session, out: ?*?*const terminal.Frame) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const frame = out orelse return status.invalid_argument;
    frame.* = s.updateFrame() catch |err| return status.fromError(err);
    return status.ok;
}

// ---- Scrolling and selection ----

pub const scroll_top: u8 = 0;
pub const scroll_bottom: u8 = 1;

/// Moves the view through the history by rows; negative goes up.
pub export fn cadex_terminal_scroll(session: ?*Session, rows: i32) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    s.scroll(rows);
    return status.ok;
}

/// CADEX_SCROLL_TOP or CADEX_SCROLL_BOTTOM.
pub export fn cadex_terminal_scroll_to(session: ?*Session, where: u8) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    switch (where) {
        scroll_top => s.scrollToTop(),
        scroll_bottom => s.scrollToBottom(),
        else => return status.invalid_argument,
    }
    return status.ok;
}

pub export fn cadex_terminal_select_press(
    session: ?*Session,
    pointer: ?*const terminal.Pointer,
    clicks: u8,
    extend: bool,
) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const p = pointer orelse return status.invalid_argument;
    s.selectPress(p.*, clicks, extend) catch |err| return status.fromError(err);
    return status.ok;
}

/// *autoscroll: -1 up, 1 down, 0 none. While not 0 and the button is down,
/// call cadex_terminal_select_autoscroll on a timer.
pub export fn cadex_terminal_select_drag(
    session: ?*Session,
    pointer: ?*const terminal.Pointer,
    autoscroll: ?*i8,
) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const p = pointer orelse return status.invalid_argument;
    const direction = s.selectDrag(p.*) catch |err| return status.fromError(err);
    if (autoscroll) |out| out.* = @intFromEnum(direction);
    return status.ok;
}

pub export fn cadex_terminal_select_autoscroll(
    session: ?*Session,
    pointer: ?*const terminal.Pointer,
    autoscroll: ?*i8,
) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const p = pointer orelse return status.invalid_argument;
    const direction = s.selectAutoscroll(p.*) catch |err| return status.fromError(err);
    if (autoscroll) |out| out.* = @intFromEnum(direction);
    return status.ok;
}

pub export fn cadex_terminal_select_release(session: ?*Session, pointer: ?*const terminal.Pointer) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const p = pointer orelse return status.invalid_argument;
    s.selectRelease(p.*);
    return status.ok;
}

pub export fn cadex_terminal_select_all(session: ?*Session) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    s.selectAll() catch |err| return status.fromError(err);
    return status.ok;
}

pub export fn cadex_terminal_select_clear(session: ?*Session) callconv(.c) void {
    if (session) |s| s.clearSelection();
}

pub export fn cadex_terminal_has_selection(session: ?*Session) callconv(.c) bool {
    const s = session orelse return false;
    return s.hasSelection();
}

/// The selected text, not NUL-terminated. Free with cadex_free. No selection
/// (or an empty one): *out is NULL and *out_len is 0.
pub export fn cadex_terminal_copy_selection(session: ?*Session, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const ptr = out orelse return status.invalid_argument;
    const len = out_len orelse return status.invalid_argument;
    ptr.* = null;
    len.* = 0;
    const text = (s.copySelection(gpa) catch |err| return status.fromError(err)) orelse return status.ok;
    if (text.len == 0) {
        gpa.free(text);
        return status.ok;
    }
    ptr.* = @constCast(text.ptr);
    len.* = text.len;
    return status.ok;
}
