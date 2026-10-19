//! The C API for what the app does to a session's view: scrolling,
//! selection, find and links (include/cadex.h). Thin, like c_api.zig.

const std = @import("std");
const status = @import("../../status.zig");
const terminal = @import("terminal.zig");
const view = terminal.view;
const Session = terminal.Session;

/// Buffers handed to the app come from malloc, freed with cadex_free.
const gpa = std.heap.c_allocator;

// ---- Scrolling and selection ----

pub const scroll_top: u8 = 0;
pub const scroll_bottom: u8 = 1;

/// Moves the view through the history by rows; negative goes up.
pub export fn cadex_terminal_scroll(session: ?*Session, rows: i32) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    view.scroll(s, rows);
    return status.ok;
}

/// CADEX_SCROLL_TOP or CADEX_SCROLL_BOTTOM.
pub export fn cadex_terminal_scroll_to(session: ?*Session, where: u8) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    switch (where) {
        scroll_top => view.scrollToTop(s),
        scroll_bottom => view.scrollToBottom(s),
        else => return status.invalid_argument,
    }
    return status.ok;
}

pub export fn cadex_terminal_select_press(
    session: ?*Session,
    pointer: ?*const view.Pointer,
    clicks: u8,
    extend: bool,
) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const p = pointer orelse return status.invalid_argument;
    view.selectPress(s, p.*, clicks, extend) catch |err| return status.fromError(err);
    return status.ok;
}

/// *autoscroll: -1 up, 1 down, 0 none. While not 0 and the button is down,
/// call cadex_terminal_select_autoscroll on a timer.
pub export fn cadex_terminal_select_drag(
    session: ?*Session,
    pointer: ?*const view.Pointer,
    autoscroll: ?*i8,
) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const p = pointer orelse return status.invalid_argument;
    const direction = view.selectDrag(s, p.*) catch |err| return status.fromError(err);
    if (autoscroll) |out| out.* = @intFromEnum(direction);
    return status.ok;
}

pub export fn cadex_terminal_select_autoscroll(
    session: ?*Session,
    pointer: ?*const view.Pointer,
    autoscroll: ?*i8,
) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const p = pointer orelse return status.invalid_argument;
    const direction = view.selectAutoscroll(s, p.*) catch |err| return status.fromError(err);
    if (autoscroll) |out| out.* = @intFromEnum(direction);
    return status.ok;
}

pub export fn cadex_terminal_select_release(session: ?*Session, pointer: ?*const view.Pointer) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const p = pointer orelse return status.invalid_argument;
    view.selectRelease(s, p.*);
    return status.ok;
}

pub export fn cadex_terminal_select_all(session: ?*Session) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    view.selectAll(s) catch |err| return status.fromError(err);
    return status.ok;
}

pub export fn cadex_terminal_select_clear(session: ?*Session) callconv(.c) void {
    if (session) |s| view.clearSelection(s);
}

pub export fn cadex_terminal_has_selection(session: ?*Session) callconv(.c) bool {
    const s = session orelse return false;
    return view.hasSelection(s);
}

/// The selected text, not NUL-terminated. Free with cadex_free. No selection
/// (or an empty one): *out is NULL and *out_len is 0.
pub export fn cadex_terminal_copy_selection(session: ?*Session, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const ptr = out orelse return status.invalid_argument;
    const len = out_len orelse return status.invalid_argument;
    ptr.* = null;
    len.* = 0;
    const text = (view.copySelection(s, gpa) catch |err| return status.fromError(err)) orelse return status.ok;
    if (text.len == 0) {
        gpa.free(text);
        return status.ok;
    }
    ptr.* = @constCast(text.ptr);
    len.* = text.len;
    return status.ok;
}

// ---- Find ----

/// Starts finding `needle` in the screen and history (ASCII letters ignore
/// case), replacing any search. len 0 stops it.
pub export fn cadex_terminal_search_start(session: ?*Session, needle: ?[*]const u8, len: usize) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const text: []const u8 = if (len == 0) "" else (needle orelse return status.invalid_argument)[0..len];
    view.searchStart(s, text) catch |err| return status.fromError(err);
    return status.ok;
}

pub export fn cadex_terminal_search_stop(session: ?*Session) callconv(.c) void {
    if (session) |s| view.searchStop(s);
}

/// CADEX_SEARCH_NEXT (toward older matches) or CADEX_SEARCH_PREVIOUS;
/// wraps, and scrolls to the match. *found: false without matches.
pub export fn cadex_terminal_search_select(session: ?*Session, direction: u8, found: ?*bool) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const d = std.enums.fromInt(view.SearchDirection, direction) orelse return status.invalid_argument;
    const selected = view.searchSelect(s, d) catch |err| return status.fromError(err);
    if (found) |out| out.* = selected;
    return status.ok;
}

/// Matches found and the current one counting from 1 (0: none).
pub export fn cadex_terminal_search_counts(session: ?*Session, total: ?*u32, current: ?*u32) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const c = view.searchCounts(s);
    if (total) |out| out.* = std.math.cast(u32, c.total) orelse std.math.maxInt(u32);
    if (current) |out| out.* = std.math.cast(u32, c.current) orelse std.math.maxInt(u32);
    return status.ok;
}

// ---- Links ----

/// Mirrors cadex_terminal_link in include/cadex.h.
pub const Link = extern struct {
    kind: u8,
    start_col: u16,
    start_row: u16,
    end_col: u16,
    end_row: u16,
};

comptime {
    std.debug.assert(@sizeOf(Link) == 10);
}

/// The link at a viewport cell. No link: out->kind is CADEX_LINK_NONE and
/// *target is NULL. Otherwise *target (not NUL-terminated, free with
/// cadex_free) is the URL or the absolute path of an existing file.
pub export fn cadex_terminal_link_at(
    session: ?*Session,
    col: u16,
    row: u16,
    out: ?*Link,
    target: ?*?[*]u8,
    target_len: ?*usize,
) callconv(.c) status.Code {
    const s = session orelse return status.invalid_argument;
    const link_out = out orelse return status.invalid_argument;
    const ptr = target orelse return status.invalid_argument;
    const len = target_len orelse return status.invalid_argument;
    link_out.* = .{ .kind = 0, .start_col = 0, .start_row = 0, .end_col = 0, .end_row = 0 };
    ptr.* = null;
    len.* = 0;

    const link = (view.linkAt(s, gpa, .{ .col = col, .row = row }) catch |err| return status.fromError(err)) orelse return status.ok;
    if (link.target.len == 0) {
        link.deinit(gpa);
        return status.ok;
    }
    link_out.* = .{
        .kind = @intFromEnum(link.kind),
        .start_col = link.start.col,
        .start_row = link.start.row,
        .end_col = link.end.col,
        .end_row = link.end.row,
    };
    ptr.* = link.target.ptr;
    len.* = link.target.len;
    return status.ok;
}
