//! Find in the terminal (⌘F): every match of a text in the screen and the
//! history, a current match that Enter and Shift+Enter move, and the
//! highlights for the frame. Wraps libghostty-vt's TerminalSearch, so it is
//! one of the files allowed to import it (ADR 0003).
//!
//! Locking: start, stop, catchUp and select read the terminal, so call them
//! with the session locked. highlight only reads the search's own state and
//! the render state, and runs without the lock, like Renderer.build.

const std = @import("std");
const vt = @import("ghostty-vt");

/// RenderState highlight tags. The current match is added first, so it
/// wins where both cover a cell.
pub const tag_match: u8 = 0;
pub const tag_current: u8 = 1;

/// How many search steps catchUp runs at most per call. Each step covers a
/// chunk of history; the cap keeps a frame from stalling on a huge one.
const max_steps_per_catch_up = 10_000;

pub const Direction = enum(u8) { next = 0, previous = 1 };

pub const Search = struct {
    active: ?vt.search.Terminal = null,

    pub fn deinit(self: *Search, terminal: *vt.Terminal) void {
        self.stop(terminal);
    }

    /// Starts searching for `needle` (ASCII letters ignore case), replacing
    /// any previous search. An empty needle just stops.
    pub fn start(self: *Search, gpa: std.mem.Allocator, terminal: *vt.Terminal, needle: []const u8) !void {
        self.stop(terminal);
        if (needle.len == 0) return;
        self.active = try .init(gpa, needle);
        self.catchUp(terminal);
    }

    pub fn stop(self: *Search, terminal: *vt.Terminal) void {
        if (self.active) |*s| s.deinit(terminal);
        self.active = null;
    }

    pub fn isActive(self: *const Search) bool {
        return self.active != null;
    }

    /// Brings the search up to date with new output. Called on every frame
    /// capture while a search is open.
    pub fn catchUp(self: *Search, terminal: *vt.Terminal) void {
        const s = if (self.active) |*a| a else return;
        s.feed(terminal, true);
        var steps: usize = 0;
        while (steps < max_steps_per_catch_up) : (steps += 1) {
            switch (s.status()) {
                .complete => return,
                .feed_required => s.feed(terminal, true),
                .running => _ = s.tick(),
            }
        }
    }

    /// Moves the current match and scrolls to it if it is off screen.
    /// next goes from the newest match toward older ones, wrapping.
    /// Returns false when there is no match.
    pub fn select(self: *Search, terminal: *vt.Terminal, direction: Direction) !bool {
        const s = if (self.active) |*a| a else return false;
        return s.select(terminal, switch (direction) {
            .next => .next,
            .previous => .prev,
        }, .if_needed);
    }

    /// Matches found so far, and the current one counting from 1 (0 when
    /// none is current), for "3 de 12" in the find bar.
    pub fn counts(self: *Search) struct { total: usize, current: usize } {
        const s = if (self.active) |*a| a else return .{ .total = 0, .current = 0 };
        const screen = s.activeScreenSearch() orelse return .{ .total = 0, .current = 0 };
        const current = if (screen.selected) |m| m.idx + 1 else 0;
        return .{ .total = screen.matchesLen(), .current = current };
    }

    /// Replaces the highlights in the render state with this search's
    /// matches on screen. Call after RenderState.endUpdate.
    pub fn highlight(self: *Search, gpa: std.mem.Allocator, state: *vt.RenderState) !void {
        const rows = state.row_data.slice();
        for (rows.items(.highlights)) |*row| row.clearRetainingCapacity();
        const s = if (self.active) |*a| a else return;
        if (s.activeScreenSearch()) |screen| {
            if (screen.selectedMatch()) |current| {
                try state.updateHighlightsFlattened(gpa, tag_current, &.{current});
            }
        }
        try state.updateHighlightsFlattened(gpa, tag_match, try s.viewportMatches());
    }
};
