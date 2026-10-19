//! What the app does to a session's view, as opposed to its process:
//! scrolling, selection, find (⌘F) and links (⌘+click). Each function takes
//! the session lock for as long as it touches the model.

const std = @import("std");
const Session = @import("session.zig").Session;
const selection = @import("selection.zig");
const search = @import("search.zig");
const links = @import("links.zig");
const pty = @import("pty.zig");

pub const Pointer = selection.Pointer;
pub const Autoscroll = selection.Autoscroll;
pub const Link = links.Link;
pub const LinkPoint = links.Point;
pub const SearchDirection = search.Direction;

/// Moves the view through the history; negative goes up.
pub fn scroll(s: *Session, rows: isize) void {
    s.lock();
    defer s.unlock();
    s.model.scroll(rows);
}

pub fn scrollToTop(s: *Session) void {
    s.lock();
    defer s.unlock();
    s.model.scrollToTop();
}

pub fn scrollToBottom(s: *Session) void {
    s.lock();
    defer s.unlock();
    s.model.scrollToBottom();
}

pub fn selectPress(s: *Session, p: Pointer, clicks: u8, extend: bool) !void {
    s.lock();
    defer s.unlock();
    try s.model.selector.press(&s.model.terminal, p, clicks, extend);
}

pub fn selectDrag(s: *Session, p: Pointer) !Autoscroll {
    s.lock();
    defer s.unlock();
    return s.model.selector.drag(&s.model.terminal, p);
}

pub fn selectAutoscroll(s: *Session, p: Pointer) !Autoscroll {
    s.lock();
    defer s.unlock();
    return s.model.selector.autoscroll(&s.model.terminal, p);
}

pub fn selectRelease(s: *Session, p: Pointer) void {
    s.lock();
    defer s.unlock();
    s.model.selector.release(&s.model.terminal, p);
}

pub fn selectAll(s: *Session) !void {
    s.lock();
    defer s.unlock();
    try selection.selectAll(&s.model.terminal);
}

pub fn clearSelection(s: *Session) void {
    s.lock();
    defer s.unlock();
    selection.clear(&s.model.terminal);
}

pub fn hasSelection(s: *Session) bool {
    s.lock();
    defer s.unlock();
    return selection.hasSelection(&s.model.terminal);
}

/// The selected text, or null without a selection. Caller frees.
pub fn copySelection(s: *Session, gpa: std.mem.Allocator) !?[:0]const u8 {
    s.lock();
    defer s.unlock();
    return selection.selectedText(&s.model.terminal, gpa);
}

// ---- Find ----

/// Starts a search, replacing the previous one; empty text stops it.
pub fn searchStart(s: *Session, needle: []const u8) !void {
    s.lock();
    defer s.unlock();
    try s.model.search.start(s.gpa, &s.model.terminal, needle);
}

pub fn searchStop(s: *Session) void {
    s.lock();
    defer s.unlock();
    s.model.search.stop(&s.model.terminal);
}

/// Moves the current match, scrolling to it. False when there is none.
pub fn searchSelect(s: *Session, direction: SearchDirection) !bool {
    s.lock();
    defer s.unlock();
    return s.model.search.select(&s.model.terminal, direction);
}

pub fn searchCounts(s: *Session) struct { total: usize, current: usize } {
    s.lock();
    defer s.unlock();
    const c = s.model.search.counts();
    return .{ .total = c.total, .current = c.current };
}

// ---- Links ----

/// The link at a viewport cell: an OSC 8 hyperlink, or a URL or existing
/// path in the text. Main thread only, like updateFrame: it refreshes the
/// frame, so a frame pointer taken before is stale after this.
pub fn linkAt(s: *Session, gpa: std.mem.Allocator, at: LinkPoint) !?Link {
    var cwd_buf: [pty.directory_buffer_size]u8 = undefined;
    var osc7_buf: [1024]u8 = undefined;

    s.lock();
    const captured = s.renderer.capture(s.gpa, &s.model.terminal, &s.model.search);
    const hyperlink = if (captured) |_| links.hyperlinkAt(gpa, &s.renderer.state, at) else |err| err;
    const reported = if (s.model.workingDirectory()) |r| links.directoryFromOsc7(r, &osc7_buf) else null;
    s.unlock();
    try captured;
    _ = try s.renderer.build(s.gpa, &s.model.search);
    if (try hyperlink) |link| return link;

    const home = if (std.c.getenv("HOME")) |h| std.mem.span(h) else null;
    const cwd = reported orelse pty.currentDirectory(s.child, &cwd_buf);
    return links.detectAt(gpa, &s.renderer, at, .{ .cwd = cwd, .home = home });
}
