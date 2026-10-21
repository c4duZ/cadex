//! The code view (docs/spec/editor.md, "Ver"): a Buffer drawn in the
//! terminal's font with line numbers, fold arrows, the core's colors, the
//! current line and the selection, wrapped at the pane's width and drawn
//! only for the rows on screen. Read-only for code (ADR 0006); the
//! markdown feature turns editing on and adds its help through Hooks.
//! Painting is in view_draw.zig, the mouse and keys in view_input.zig.

const std = @import("std");
const gfx = @import("gfx");
const ui_mod = @import("ui");
const Buffer = @import("buffer.zig").Buffer;
const Change = @import("buffer.zig").Change;
const Syntax = @import("syntax.zig").Syntax;
const Folding = @import("folding.zig").Folding;
const Rows = @import("rows.zig").Rows;
const Find = @import("find.zig").Find;
const appearance = @import("appearance.zig");
const view_draw = @import("view_draw.zig");
const view_input = @import("view_input.zig");

const Ui = ui_mod.Ui;

/// A line under part of the text (a broken link), in byte offsets.
pub const Underline = struct { start: usize, end: usize, color: gfx.Color };

/// What another feature adds to a view (markdown: suggestions, links).
pub const Hooks = struct {
    context: *anyopaque,
    /// Before the view takes this frame's keys: the suggestions keep the
    /// arrows, Enter, Tab and Esc while they show.
    keys: ?*const fn (context: *anyopaque, u: *Ui, view: *View) void = null,
    /// After the text changed (typed, pasted, undone), once per change.
    changed: ?*const fn (context: *anyopaque, view: *View) void = null,
    /// Ctrl+click on byte `at`; true when it did something (opened a link),
    /// so the click does not move the caret.
    ctrl_click: ?*const fn (context: *anyopaque, view: *View, at: usize) bool = null,
    /// Lines under parts of the text, drawn after it.
    underlines: ?*const fn (context: *anyopaque) []const Underline = null,
    /// Draws over the view after everything (a popup, a button).
    overlay: ?*const fn (context: *anyopaque, u: *Ui, view: *View, area: gfx.Rect) void = null,
    /// The pane is gone: free what the hooks hold.
    closed: ?*const fn (context: *anyopaque) void = null,
};

pub const Options = struct {
    editable: bool = false,
};

/// The geometry of the last frame, for the mouse and the keys.
pub const Metrics = struct {
    spec: gfx.FontSpec = .{ .family = "", .size = 0 },
    cell_w: f32 = 8,
    row_h: f32 = 18,
    /// Where the text starts (right of the gutter) and its rectangle.
    text: gfx.Rect = .{},
    gutter: gfx.Rect = .{},
    view_rows: usize = 1,
};

pub const View = struct {
    gpa: std.mem.Allocator,
    id: ui_mod.Id,
    buffer: Buffer,
    syntax: Syntax = .{},
    folding: Folding = .{},
    rows: Rows = .{},
    scroll: ui_mod.list.Scroll = .{},
    find: Find = .{},
    editable: bool,
    hooks: ?Hooks = null,
    metrics: Metrics = .{},
    /// The column Up and Down keep while going through shorter lines.
    goal_col: ?usize = null,
    /// Scroll to the caret on the next frame (it moved by a key or an edit).
    reveal_caret: bool = false,
    /// Center this line on the next frame (opening at a search result).
    reveal_line: ?usize = null,
    /// The core's folds are out of date after an edit.
    folds_stale: bool = false,
    /// What Tab inserts: a tab or some spaces, from the file.
    indent: []const u8 = "    ",
    /// For the measures that only change with the font.
    measured_size: f32 = 0,
    digit_w: f32 = 8,

    /// `file_name` picks the language; `highlight` false for big files.
    pub fn create(gpa: std.mem.Allocator, id: ui_mod.Id, file_name: []const u8, initial: []const u8, highlight: bool, options: Options) !*View {
        const self = try gpa.create(View);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .id = id, .buffer = try Buffer.init(gpa, initial), .editable = options.editable };
        self.buffer.caret = 0;
        self.buffer.anchor = 0;
        self.buffer.listener = .{ .context = self, .changed = bufferChanged };
        self.syntax = Syntax.open(gpa, file_name, initial, highlight);
        self.indent = detectIndent(initial);
        self.refreshFolds();
        return self;
    }

    pub fn destroy(self: *View) void {
        self.syntax.close();
        self.buffer.deinit();
        self.folding.deinit(self.gpa);
        self.rows.deinit(self.gpa);
        self.find.deinit(self.gpa);
        self.gpa.destroy(self);
    }

    pub fn text(self: *const View) []const u8 {
        return self.buffer.text();
    }

    /// New text from disk, keeping the caret and the scroll where they were.
    pub fn replaceAll(self: *View, file_name: []const u8, value: []const u8, highlight: bool) !void {
        try self.buffer.setText(value);
        self.syntax.close();
        self.syntax = Syntax.open(self.gpa, file_name, value, highlight);
        self.refreshFolds();
        if (self.hooks) |h| if (h.changed) |f| f(h.context, self);
    }

    fn bufferChanged(context: *anyopaque, buffer: *const Buffer, change: Change) void {
        const self: *View = @ptrCast(@alignCast(context));
        self.syntax.edit(change.start, change.old_end, buffer.text()[change.start..change.new_end]);
        // Line numbers moved under the folds: open them rather than hide
        // the wrong lines (the Mac's rule).
        self.folding.unfoldAll();
        self.folds_stale = true;
        self.reveal_caret = true;
        if (self.hooks) |h| if (h.changed) |f| f(h.context, self);
    }

    pub fn refreshFolds(self: *View) void {
        self.folds_stale = false;
        const list = self.syntax.folds(self.gpa);
        defer if (list.len > 0) self.gpa.free(list);
        self.folding.setRegions(self.gpa, list) catch {};
    }

    pub fn foldAll(self: *View) void {
        self.folding.foldAll(self.gpa) catch {};
    }

    pub fn unfoldAll(self: *View) void {
        self.folding.unfoldAll();
    }

    /// Replaces [start, end) with `value` as one undo step, caret after it
    /// (a chosen suggestion).
    pub fn replaceRange(self: *View, start: usize, end: usize, value: []const u8) void {
        if (!self.editable) return;
        self.buffer.replace(start, end, value, .other) catch {};
    }

    /// Puts the caret at the start of 1-based `line`, centered on screen.
    pub fn goToLine(self: *View, line: usize) void {
        const index = @min(line -| 1, self.buffer.lineCount() - 1);
        self.buffer.place(self.buffer.lineStart(index), false);
        self.reveal_line = index;
    }

    /// Draws in `area` and answers this frame's mouse and, when `focused`, keys.
    pub fn draw(self: *View, u: *Ui, area: gfx.Rect, focused: bool) void {
        if (self.folds_stale) self.refreshFolds();
        self.measure(u, area);
        self.rows.update(self.gpa, &self.buffer, &self.folding, self.columns()) catch return;
        // The wheel first, three rows a notch as Windows scrolls; the bar is
        // drawn last, over the text.
        if (u.mouseOver(area) and u.input.wheel != 0) {
            self.scroll.offset -= @as(f32, @floatFromInt(u.input.wheel)) / 120 * 3 * self.metrics.row_h;
            u.input.wheel = 0;
        }
        view_input.mouse(self, u, area);
        if (focused) view_input.keys(self, u);
        self.rows.update(self.gpa, &self.buffer, &self.folding, self.columns()) catch return;
        const content = @as(f32, @floatFromInt(self.rows.count() + 1)) * self.metrics.row_h;
        self.revealPending();
        self.scroll.clamp(content, area.h);
        view_draw.draw(self, u, area, focused);
        ui_mod.list.scrollArea(u, self.id, area, content, &self.scroll);
        if (self.find.open) self.find.draw(u, self, area);
        if (self.hooks) |h| if (h.overlay) |f| f(h.context, u, self, area);
    }

    /// The font, the cell, the gutter and the text rectangle for `area`.
    fn measure(self: *View, u: *Ui, area: gfx.Rect) void {
        const look = &appearance.current;
        var m = &self.metrics;
        m.spec = look.font(u.style.window_scale);
        if (m.spec.size != self.measured_size) {
            self.measured_size = m.spec.size;
            // Ten cells measured at once: the width of one, without rounding.
            m.cell_w = @max(u.painter.measure("0000000000", m.spec) / 10, 1);
            self.digit_w = u.painter.measure("0000000000", self.numberSpec()) / 10;
        }
        m.row_h = @round(m.spec.size * 1.45);
        var digits: usize = 3;
        var n = self.buffer.lineCount();
        while (n >= 1000) : (n /= 10) digits += 1;
        var rest = area;
        m.gutter = rest.takeLeft(@as(f32, @floatFromInt(digits)) * self.digit_w + u.px(14 + 14));
        _ = rest.takeLeft(u.px(4));
        // Clear of the scrollbar.
        _ = rest.takeRight(u.px(12));
        m.text = rest;
        m.view_rows = @max(@as(usize, @intFromFloat(area.h / m.row_h)), 1);
    }

    pub fn numberSpec(self: *const View) gfx.FontSpec {
        var spec = self.metrics.spec;
        spec.size = @max(@round(spec.size * 0.85), 9);
        return spec;
    }

    /// Columns per row: the text's width in cells.
    pub fn columns(self: *const View) usize {
        return @max(@as(usize, @intFromFloat(self.metrics.text.w / self.metrics.cell_w)), 8);
    }

    /// The y of row `i`, on screen.
    pub fn rowY(self: *const View, i: usize) f32 {
        return self.metrics.text.y + @as(f32, @floatFromInt(i)) * self.metrics.row_h - self.scroll.offset;
    }

    /// Where the caret is on screen (after a draw): suggestions go below it.
    pub fn caretRect(self: *const View) gfx.Rect {
        const i = self.rows.rowOf(self.buffer.caret);
        if (i >= self.rows.count()) return .{ .x = self.metrics.text.x, .y = self.metrics.text.y, .w = 1, .h = self.metrics.row_h };
        const x = view_draw.xOf(self, self.rows.items.items[i], self.buffer.caret);
        return .{ .x = x, .y = self.rowY(i), .w = self.metrics.cell_w, .h = self.metrics.row_h };
    }

    fn revealPending(self: *View) void {
        const h = self.metrics.text.h;
        if (self.reveal_line) |line| {
            self.reveal_line = null;
            self.reveal_caret = false;
            const y = @as(f32, @floatFromInt(self.rows.rowOfLine(line))) * self.metrics.row_h;
            self.scroll.offset = @max(y - h / 2, 0);
            return;
        }
        if (!self.reveal_caret) return;
        self.reveal_caret = false;
        const r = self.rows.rowOf(self.buffer.caret);
        self.scroll.reveal(@as(f32, @floatFromInt(r)) * self.metrics.row_h, self.metrics.row_h, h);
    }
};

/// The tab or the number of spaces most lines start with (the Mac's
/// CodeTextView.detectIndent).
pub fn detectIndent(value: []const u8) []const u8 {
    var tabs: usize = 0;
    var twos: usize = 0;
    var fours: usize = 0;
    var lines = std.mem.splitScalar(u8, value[0..@min(value.len, 256 * 1024)], '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (line[0] == '\t') {
            tabs += 1;
            continue;
        }
        var n: usize = 0;
        while (n < line.len and line[n] == ' ') n += 1;
        if (n >= 2 and n % 4 != 0 and n % 2 == 0) twos += 1;
        if (n >= 4 and n % 4 == 0) fours += 1;
    }
    if (tabs > twos + fours) return "\t";
    // Lines at 2 or 6 spaces only happen with a unit of 2.
    return if (twos * 4 >= fours and twos > 0) "  " else "    ";
}

test "the indent unit comes from the lines" {
    try std.testing.expectEqualStrings("\t", detectIndent("a\n\tb\n\tc\n"));
    try std.testing.expectEqualStrings("  ", detectIndent("a\n  b\n    c\n  d\n"));
    try std.testing.expectEqualStrings("    ", detectIndent("a\n    b\n        c\n"));
}

test {
    @import("win32").refAllDeep(@This());
}
