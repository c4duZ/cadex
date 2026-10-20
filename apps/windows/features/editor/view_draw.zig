//! Painting a View (view.zig), in the Mac's order: the background, the
//! current line, search matches, the selection, the text in the core's
//! colors one row at a time, underlines, the caret with the IME's text,
//! and the gutter with numbers and fold arrows. Only the rows on screen.

const std = @import("std");
const gfx = @import("gfx");
const ui_mod = @import("ui");
const icons = @import("icons");
const wrap = @import("wrap.zig");
const appearance = @import("appearance.zig");
const View = @import("view.zig").View;
const Row = @import("rows.zig").Row;
const Span = @import("syntax.zig").Span;

const Ui = ui_mod.Ui;
const Color = gfx.Color;

/// The rows in view: [first, last).
pub fn visibleRows(view: *const View, area: gfx.Rect) struct { first: usize, last: usize } {
    const row_h = view.metrics.row_h;
    const first: usize = @intFromFloat(@max(view.scroll.offset / row_h, 0));
    const shown: usize = @intFromFloat(@ceil(area.h / row_h) + 1);
    const n = view.rows.count();
    return .{ .first = @min(first, n), .last = @min(first + shown, n) };
}

pub fn draw(view: *View, u: *Ui, area: gfx.Rect, focused: bool) void {
    const look = &appearance.current;
    const p = u.painter;
    p.fill(area, look.background);
    p.pushClip(area);
    defer p.popClip();
    var arena_state: std.heap.ArenaAllocator = .init(view.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const range = visibleRows(view, area);
    if (range.first == range.last) return;
    const rows = view.rows.items.items[range.first..range.last];
    const sel = view.buffer.selection();
    const caret_line = view.buffer.lineOf(view.buffer.caret);
    const full_w = area.right() - view.metrics.text.x;

    for (rows, range.first..) |row, i| {
        const y = view.rowY(i);
        if (sel.start == sel.end and row.line == caret_line) {
            p.fill(.{ .x = view.metrics.gutter.x, .y = y, .w = area.w, .h = view.metrics.row_h }, look.current_line);
        }
        drawMatches(p, view, row, y);
        if (sel.start != sel.end) drawSelection(p, view, row, y, sel.start, sel.end, look.selection);
    }
    const spans = view.syntax.spans(arena, rows[0].start, rows[rows.len - 1].end);
    var next_span: usize = 0;
    for (rows, range.first..) |row, i| {
        drawRow(view, u, arena, row, view.rowY(i), full_w, spans, &next_span);
    }
    drawUnderlines(p, view, rows, range.first);
    drawCaret(view, u, focused);
    drawGutter(view, u, rows, range.first, caret_line);
}

/// The x of byte `at` on `row`.
pub fn xOf(view: *const View, row: Row, at: usize) f32 {
    const col = wrap.columnOf(view.text(), row.start, @min(at, row.end));
    return view.metrics.text.x + @as(f32, @floatFromInt(col)) * view.metrics.cell_w;
}

fn drawSelection(p: *gfx.Painter, view: *const View, row: Row, y: f32, start: usize, end: usize, color: Color) void {
    if (end < row.start or start > row.end) return;
    if (start == row.end and !row.last) return;
    const x0 = xOf(view, row, @max(start, row.start));
    var x1 = xOf(view, row, @min(end, row.end));
    // The line end is selected too: a cell past the text shows it.
    if (end > row.end and row.last) x1 += view.metrics.cell_w;
    p.fill(.{ .x = x0, .y = y, .w = x1 - x0, .h = view.metrics.row_h }, color);
}

fn drawMatches(p: *gfx.Painter, view: *const View, row: Row, y: f32) void {
    if (!view.find.open or view.find.matches.items.len == 0) return;
    const len = view.find.query().len;
    const amber = Color.rgb(0xf5c542).alpha(0.35);
    const orange = Color.rgb(0xff8c1a).alpha(0.6);
    for (view.find.matchesIn(row.start, row.end)) |m| {
        const current = if (view.find.current) |c| view.find.matches.items[c] == m else false;
        drawSelection(p, view, row, y, m, m + len, if (current) orange else amber);
    }
}

fn drawRow(view: *const View, u: *Ui, arena: std.mem.Allocator, row: Row, y: f32, w: f32, spans: []const Span, next_span: *usize) void {
    var shown: std.ArrayList(u8) = .empty;
    var map: std.ArrayList(u32) = .empty;
    wrap.display(arena, view.text(), row.start, row.end, &shown, &map) catch return;
    if (shown.items.len == 0) return;
    var runs: std.ArrayList(gfx.ColorRun) = .empty;
    const look = &appearance.current;
    // Spans come in order: skip the ones before this row, keep the one
    // that may go on to the next.
    while (next_span.* < spans.len and spans[next_span.*].end <= row.start) next_span.* += 1;
    var k = next_span.*;
    while (k < spans.len and spans[k].start < row.end) : (k += 1) {
        const s = spans[k];
        const from = @max(s.start, row.start) - row.start;
        const to = @min(s.end, row.end) - row.start;
        runs.append(arena, .{ .start = map.items[from], .end = map.items[to], .color = look.token(s.kind) }) catch break;
    }
    const r: gfx.Rect = .{ .x = view.metrics.text.x, .y = y, .w = w, .h = view.metrics.row_h };
    u.painter.textColored(shown.items, view.metrics.spec, r, look.foreground, runs.items);
}

fn drawUnderlines(p: *gfx.Painter, view: *const View, rows: []const Row, first: usize) void {
    const h = view.hooks orelse return;
    const get = h.underlines orelse return;
    const lines = get(h.context);
    const thick = @max(1, @round(view.metrics.spec.size / 14));
    for (rows, first..) |row, i| {
        const y = view.rowY(i) + view.metrics.row_h - thick * 2;
        for (lines) |l| {
            if (l.end <= row.start or l.start >= row.end) continue;
            const x0 = xOf(view, row, @max(l.start, row.start));
            const x1 = xOf(view, row, @min(l.end, row.end));
            // Dotted, as the Mac draws a broken link: a dot every other step.
            var x = x0;
            while (x < x1) : (x += thick * 3) {
                p.fill(.{ .x = x, .y = y, .w = @min(thick * 1.5, x1 - x), .h = thick }, l.color);
            }
        }
    }
}

fn drawCaret(view: *View, u: *Ui, focused: bool) void {
    if (!focused) return;
    const b = &view.buffer;
    const i = view.rows.rowOf(b.caret);
    if (i >= view.rows.count()) return;
    const row = view.rows.items.items[i];
    const x = xOf(view, row, b.caret);
    const y = view.rowY(i);
    const m = view.metrics;
    const caret: gfx.Rect = .{ .x = x, .y = y + m.row_h * 0.1, .w = @max(1, u.px(1.5)), .h = m.row_h * 0.8 };
    u.ime_caret = .{ .x = x, .y = y, .w = m.cell_w, .h = m.row_h };
    const look = &appearance.current;
    if (u.input.composition.items.len > 0) {
        // The IME's text in progress, underlined, where it will land.
        const width = u.painter.measure(u.input.composition.items, m.spec);
        u.painter.fill(.{ .x = x, .y = y, .w = width, .h = m.row_h }, look.background);
        u.painter.text(u.input.composition.items, m.spec, .{ .x = x, .y = y, .w = width + 4, .h = m.row_h }, look.foreground, .{ .ellipsis = false });
        u.painter.fill(.{ .x = x, .y = y + m.row_h - @max(1, u.px(1)), .w = width, .h = @max(1, u.px(1)) }, look.foreground);
        return;
    }
    // Blinks every 530 ms, the Windows default caret rate.
    if (@mod(@divTrunc(u.now_ms, 530), 2) == 0) u.painter.fill(caret, look.foreground);
    u.requestFrame(530 - @as(u32, @intCast(@mod(u.now_ms, 530))));
}

fn drawGutter(view: *const View, u: *Ui, rows: []const Row, first: usize, caret_line: usize) void {
    const look = &appearance.current;
    const m = view.metrics;
    const p = u.painter;
    p.fill(.{ .x = m.gutter.x, .y = m.gutter.y, .w = m.gutter.w, .h = m.gutter.h }, look.background.alpha(0.6));
    const arrow_w = u.px(14);
    const spec = view.numberSpec();
    for (rows, first..) |row, i| {
        if (!row.first) continue;
        const y = view.rowY(i);
        var buf: [16]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "{d}", .{row.line + 1}) catch continue;
        const color = if (row.line == caret_line) look.foreground.alpha(0.85) else look.line_number;
        const box: gfx.Rect = .{ .x = m.gutter.x, .y = y, .w = m.gutter.w - arrow_w - u.px(6), .h = m.row_h };
        p.text(label, spec, box, color, .{ .@"align" = .trailing, .ellipsis = false });
        if (view.folding.regionAt(row.line) != null) {
            const glyph = if (view.folding.isFolded(row.line)) icons.phosphor.caret_right else icons.phosphor.caret_down;
            p.icon(glyph, u.px(11), .{ .x = m.gutter.right() - arrow_w - u.px(2), .y = y, .w = arrow_w, .h = m.row_h }, look.line_number);
        }
    }
}

/// Whether a click at x in the gutter is on the fold arrow.
pub fn onArrow(view: *const View, u: *Ui, x: f32) bool {
    return x >= view.metrics.gutter.right() - u.px(18);
}

test {
    @import("win32").refAllDeep(@This());
}
