//! Turns libghostty-vt's RenderState into the flat frame the apps draw:
//! colors already resolved to RGB, cell text as UTF-8, no libghostty types.
//! With model.zig, the only file that touches libghostty-vt (ADR 0003).
//! Mirrors cadex_terminal_cell / cadex_terminal_frame in include/cadex.h.

const std = @import("std");
const vt = @import("ghostty-vt");
const search = @import("search.zig");

/// libghostty-vt style id of the default style (style.zig: default_id).
const default_style_id = 0;

pub const CellFlags = struct {
    pub const bold: u16 = 1 << 0;
    pub const italic: u16 = 1 << 1;
    pub const faint: u16 = 1 << 2;
    pub const strikethrough: u16 = 1 << 3;
    /// First half of a double-width character: draw it across two cells.
    pub const wide: u16 = 1 << 4;
    /// Second half of a wide character, or the end-of-line wrap marker of
    /// one: draw nothing here.
    pub const spacer: u16 = 1 << 5;
    /// bg differs from the frame background; otherwise skip drawing it.
    pub const has_background: u16 = 1 << 6;
    /// Inside the text selection.
    pub const selected: u16 = 1 << 7;
    /// Underline kind in bits 8..10: 0 none, 1 single, 2 double, 3 curly,
    /// 4 dotted, 5 dashed.
    pub const underline_shift: u4 = 8;
    /// A match of the open search (⌘F), and the current one.
    pub const match: u16 = 1 << 11;
    pub const match_current: u16 = 1 << 12;
};

pub const Cell = extern struct {
    /// Foreground and background as 0xRRGGBB.
    fg: u32,
    bg: u32,
    /// The cell's text in Frame.text; length 0 for an empty cell.
    text_offset: u32,
    text_len: u16,
    flags: u16,
};

pub const CursorStyle = struct {
    pub const block: u8 = 0;
    pub const bar: u8 = 1;
    pub const underline: u8 = 2;
    pub const block_hollow: u8 = 3;
};

pub const Frame = extern struct {
    cells: [*]const Cell,
    text: [*]const u8,
    text_len: u32,
    background: u32,
    foreground: u32,
    cursor_color: u32,
    cols: u16,
    rows: u16,
    cursor_x: u16,
    cursor_y: u16,
    cursor_style: u8,
    cursor_visible: bool,
    cursor_blinking: bool,
    has_cursor_color: bool,
    /// Rows of history plus screen, and the first row shown: the viewport
    /// is at the bottom when scroll_offset + rows == scroll_total.
    scroll_total: u32,
    scroll_offset: u32,
};

pub const Renderer = struct {
    state: vt.RenderState = .empty,
    cells: std.ArrayList(Cell) = .empty,
    text: std.ArrayList(u8) = .empty,
    frame: Frame = undefined,
    scrollbar: vt.PageList.Scrollbar = .zero,

    pub fn deinit(self: *Renderer, gpa: std.mem.Allocator) void {
        self.state.deinit(gpa);
        self.cells.deinit(gpa);
        self.text.deinit(gpa);
    }

    /// First phase: needs exclusive access to the terminal (hold the
    /// session lock). Kept short so the reader thread is not held up.
    pub fn capture(self: *Renderer, gpa: std.mem.Allocator, terminal: *vt.Terminal, find: ?*search.Search) !void {
        if (find) |f| f.catchUp(terminal);
        try self.state.beginUpdate(gpa, terminal);
        self.scrollbar = terminal.screens.active.pages.scrollbar();
    }

    /// Second phase: only touches memory this renderer owns, so it runs
    /// without the lock. The frame stays valid until the next capture.
    pub fn build(self: *Renderer, gpa: std.mem.Allocator, find: ?*search.Search) !*const Frame {
        self.state.endUpdate();
        if (find) |f| try f.highlight(gpa, &self.state);
        const s = &self.state;
        const cols: usize = s.cols;
        const rows: usize = s.rows;

        try self.cells.resize(gpa, cols * rows);
        self.text.clearRetainingCapacity();

        const row_cells = s.row_data.items(.cells);
        const row_selections = s.row_data.items(.selection);
        const row_highlights = s.row_data.items(.highlights);
        for (0..rows) |y| {
            const row = row_cells[y].slice();
            for (0..cols) |x| {
                const out = &self.cells.items[y * cols + x];
                if (x >= row.len) {
                    out.* = blankCell(s);
                } else {
                    out.* = try self.translateCell(gpa, row.get(x));
                }
                // The range is inclusive on both ends.
                if (row_selections[y]) |range| {
                    if (x >= range[0] and x <= range[1]) out.flags |= CellFlags.selected;
                }
                out.flags |= matchFlags(row_highlights[y].items, x);
            }
        }

        self.frame = .{
            .cells = self.cells.items.ptr,
            .text = self.text.items.ptr,
            .text_len = @intCast(self.text.items.len),
            .background = rgb(s.colors.background),
            .foreground = rgb(s.colors.foreground),
            .cursor_color = if (s.colors.cursor) |c| rgb(c) else 0,
            .has_cursor_color = s.colors.cursor != null,
            .cols = s.cols,
            .rows = s.rows,
            .cursor_x = if (s.cursor.viewport) |v| v.x else 0,
            .cursor_y = if (s.cursor.viewport) |v| v.y else 0,
            .cursor_visible = s.cursor.visible and s.cursor.viewport != null,
            .cursor_blinking = s.cursor.blinking,
            .cursor_style = cursorStyle(s.cursor.visual_style),
            .scroll_total = @intCast(@min(self.scrollbar.total, std.math.maxInt(u32))),
            .scroll_offset = @intCast(@min(self.scrollbar.offset, std.math.maxInt(u32))),
        };
        return &self.frame;
    }

    fn translateCell(self: *Renderer, gpa: std.mem.Allocator, cell: vt.RenderState.Cell) !Cell {
        const s = &self.state;
        // RenderState leaves `style` undefined for cells with the default style
        // (style_id 0); reading it there is garbage.
        const style: vt.Style = if (cell.raw.style_id != default_style_id) cell.style else .{};
        const palette = &s.colors.palette;

        // Bold with a palette color uses the bright variant, like xterm.
        var fg = style.fg(.{ .default = s.colors.foreground, .palette = palette, .bold = .bright });
        const explicit_bg = style.bg(&cell.raw, palette);
        var bg = explicit_bg orelse s.colors.background;
        var flags: u16 = 0;
        if (explicit_bg != null) flags |= CellFlags.has_background;
        if (style.flags.inverse) {
            std.mem.swap(vt.color.RGB, &fg, &bg);
            flags |= CellFlags.has_background;
        }

        if (style.flags.bold) flags |= CellFlags.bold;
        if (style.flags.italic) flags |= CellFlags.italic;
        if (style.flags.faint) flags |= CellFlags.faint;
        if (style.flags.strikethrough) flags |= CellFlags.strikethrough;
        flags |= @as(u16, @intFromEnum(style.flags.underline)) << CellFlags.underline_shift;
        switch (cell.raw.wide) {
            .wide => flags |= CellFlags.wide,
            .spacer_tail, .spacer_head => flags |= CellFlags.spacer,
            .narrow => {},
        }

        const offset: u32 = @intCast(self.text.items.len);
        if (!style.flags.invisible) try self.appendText(gpa, cell);
        return .{
            .fg = rgb(fg),
            .bg = rgb(bg),
            .text_offset = offset,
            .text_len = @intCast(self.text.items.len - offset),
            .flags = flags,
        };
    }

    fn appendText(self: *Renderer, gpa: std.mem.Allocator, cell: vt.RenderState.Cell) !void {
        const first = cell.raw.codepoint();
        if (first == 0) return;
        try appendCodepoint(gpa, &self.text, first);
        // Graphemes (emoji with modifiers, combining accents) carry the
        // rest of their codepoints separately.
        // `grapheme` is undefined unless the cell is tagged as one.
        if (cell.raw.content_tag != .codepoint_grapheme) return;
        for (cell.grapheme) |cp| try appendCodepoint(gpa, &self.text, cp);
    }
};

/// Search flags for column x. The current match was added first, so the
/// first highlight covering x decides.
fn matchFlags(highlights: []const vt.RenderState.Highlight, x: usize) u16 {
    for (highlights) |h| {
        if (x < h.range[0] or x > h.range[1]) continue;
        return if (h.tag == search.tag_current) CellFlags.match_current else CellFlags.match;
    }
    return 0;
}

fn appendCodepoint(gpa: std.mem.Allocator, text: *std.ArrayList(u8), cp: u21) !void {
    var buf: [4]u8 = undefined;
    // An invalid codepoint from the program is shown as U+FFFD, not dropped.
    const len = std.unicode.utf8Encode(cp, &buf) catch std.unicode.utf8Encode(0xFFFD, &buf) catch unreachable;
    try text.appendSlice(gpa, buf[0..len]);
}

fn blankCell(s: *const vt.RenderState) Cell {
    return .{ .fg = rgb(s.colors.foreground), .bg = rgb(s.colors.background), .text_offset = 0, .text_len = 0, .flags = 0 };
}

fn rgb(c: vt.color.RGB) u32 {
    return (@as(u32, c.r) << 16) | (@as(u32, c.g) << 8) | c.b;
}

fn cursorStyle(style: anytype) u8 {
    return switch (style) {
        .bar => CursorStyle.bar,
        .underline => CursorStyle.underline,
        .block_hollow => CursorStyle.block_hollow,
        else => CursorStyle.block,
    };
}

// Layout shared with include/cadex.h, which asserts the same sizes.
comptime {
    std.debug.assert(@sizeOf(Cell) == 16);
    std.debug.assert(@sizeOf(Frame) == 56);
}
