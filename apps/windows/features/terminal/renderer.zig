//! Draws a frame of the core (cadex_terminal_frame) in a rectangle, in the
//! Mac's painting order: cell backgrounds, selection, find matches, a block
//! cursor, glyphs, underline and strikethrough, thin cursors, the
//! scrollbar. Glyphs go in runs of one face and color per row; a cell the
//! font cannot draw alone (emoji, a combined grapheme) goes through a
//! DirectWrite layout, which picks a fallback font.

const std = @import("std");
const gfx = @import("gfx");
const cadex = @import("cadex");
const font_mod = @import("font.zig");

const Font = font_mod.Font;
const Color = gfx.Color;

/// Find highlights and the selection over the text, as on the Mac.
const match_color = Color.rgb(0xE5B341).alpha(0.35);
const current_match_color = Color.rgb(0xFF9F0A).alpha(0.7);
const selection_alpha = 0.3;
const flash_alpha = 0.12;

pub const Overlay = struct {
    /// The theme's selection color (opaque, under the text); else the text color, faint.
    selection: ?u32 = null,
    /// A link under the pointer with Ctrl held: underlined.
    link: ?cadex.cadex_terminal_link = null,
    hide_cursor: bool = false,
    /// The bell's flash, 0 to 1.
    flash: f32 = 0,
    /// Unfocused panes draw the cursor hollow.
    focused: bool = true,
    /// The IME's text in progress, at the cursor.
    composition: []const u8 = "",
    show_scrollbar: bool = false,
};

const max_run = 512;

pub fn draw(p: *gfx.Painter, font: *Font, frame: *const cadex.cadex_terminal_frame, area: gfx.Rect, padding: f32, overlay: Overlay) void {
    const m = font.metrics;
    p.fill(area, Color.rgb(frame.background));
    const cols: usize = frame.cols;
    const rows: usize = frame.rows;
    if (cols == 0 or rows == 0) return;
    const cells = frame.cells[0 .. cols * rows];
    const text = frame.text[0..frame.text_len];
    const ox = area.x + padding;
    const oy = area.y + padding;
    const cell_rect = struct {
        fn at(x0: f32, y0: f32, mm: font_mod.Metrics, col: usize, row: usize, span: usize) gfx.Rect {
            return .{ .x = x0 + @as(f32, @floatFromInt(col)) * mm.cell_width, .y = y0 + @as(f32, @floatFromInt(row)) * mm.cell_height, .w = mm.cell_width * @as(f32, @floatFromInt(span)), .h = mm.cell_height };
        }
    }.at;
    const cursor_at: ?usize = if (frame.cursor_visible and !overlay.hide_cursor and frame.cursor_x < cols and frame.cursor_y < rows) @as(usize, frame.cursor_y) * cols + frame.cursor_x else null;
    const cursor_color = Color.rgb(if (frame.has_cursor_color) frame.cursor_color else frame.foreground);
    const block = frame.cursor_style == cadex.CADEX_CURSOR_BLOCK and overlay.focused;

    // Backgrounds, merged across a row while the color stays.
    for (0..rows) |row| {
        var col: usize = 0;
        while (col < cols) {
            const cell = cells[row * cols + col];
            if (cell.flags & cadex.CADEX_CELL_HAS_BACKGROUND == 0) {
                col += 1;
                continue;
            }
            var end = col + 1;
            while (end < cols and cells[row * cols + end].flags & cadex.CADEX_CELL_HAS_BACKGROUND != 0 and cells[row * cols + end].bg == cell.bg) end += 1;
            p.fill(cell_rect(ox, oy, m, col, row, end - col), Color.rgb(cell.bg));
            col = end;
        }
    }
    const selection = if (overlay.selection) |s| Color.rgb(s) else Color.rgb(frame.foreground).alpha(selection_alpha);
    for (cells, 0..) |cell, i| {
        if (cell.flags & cadex.CADEX_CELL_SELECTED != 0) p.fill(cell_rect(ox, oy, m, i % cols, i / cols, 1), selection);
        if (cell.flags & cadex.CADEX_CELL_MATCH_CURRENT != 0) {
            p.fill(cell_rect(ox, oy, m, i % cols, i / cols, 1), current_match_color);
        } else if (cell.flags & cadex.CADEX_CELL_MATCH != 0) {
            p.fill(cell_rect(ox, oy, m, i % cols, i / cols, 1), match_color);
        }
    }
    if (cursor_at) |at| if (block) p.fill(cell_rect(ox, oy, m, at % cols, at / cols, 1), cursor_color);

    drawGlyphs(p, font, frame, cells, text, ox, oy, cursor_at, block);
    drawLines(p, font, cells, ox, oy, cols, frame.background);
    if (overlay.link) |link| underlineLink(p, m, link, ox, oy, cols, Color.rgb(frame.foreground));

    if (cursor_at) |at| if (!block) {
        const r = cell_rect(ox, oy, m, at % cols, at / cols, 1);
        const thin = @max(1, @round(m.cell_width / 8));
        switch (frame.cursor_style) {
            cadex.CADEX_CURSOR_BAR => p.fill(.{ .x = r.x, .y = r.y, .w = thin * 1.5, .h = r.h }, cursor_color),
            cadex.CADEX_CURSOR_UNDERLINE => p.fill(.{ .x = r.x, .y = r.bottom() - thin * 1.5, .w = r.w, .h = thin * 1.5 }, cursor_color),
            else => p.stroke(r, 0, cursor_color, thin),
        }
    };
    if (overlay.composition.len > 0) if (cursor_at orelse lastCursor(frame, cols)) |at| {
        const r = cell_rect(ox, oy, m, at % cols, at / cols, 1);
        const spec: gfx.FontSpec = .{ .family = font.family, .size = m.em };
        const width = p.measure(overlay.composition, spec);
        p.fill(.{ .x = r.x, .y = r.y, .w = width, .h = r.h }, Color.rgb(frame.background));
        p.text(overlay.composition, spec, .{ .x = r.x, .y = r.y, .w = width + m.cell_width, .h = r.h }, Color.rgb(frame.foreground), .{ .ellipsis = false });
        p.fill(.{ .x = r.x, .y = r.bottom() - 1, .w = width, .h = 1 }, Color.rgb(frame.foreground));
    };
    if (overlay.show_scrollbar and frame.scroll_total > frame.rows) {
        const total: f32 = @floatFromInt(frame.scroll_total);
        const track_h = area.h - 2 * padding;
        const thumb_h = @max(track_h * @as(f32, @floatFromInt(frame.rows)) / total, 12);
        const y = area.y + padding + (track_h - thumb_h) * @as(f32, @floatFromInt(frame.scroll_offset)) / @max(total - @as(f32, @floatFromInt(frame.rows)), 1);
        p.fillRounded(.{ .x = area.right() - padding / 2 - 2, .y = y, .w = 3, .h = thumb_h }, 1.5, Color.rgb(frame.foreground).alpha(0.35));
    }
    if (overlay.flash > 0) p.fill(area, Color.rgb(frame.foreground).alpha(flash_alpha * overlay.flash));
}

fn lastCursor(frame: *const cadex.cadex_terminal_frame, cols: usize) ?usize {
    if (frame.cursor_x >= cols or frame.cursor_y >= frame.rows) return null;
    return @as(usize, frame.cursor_y) * cols + frame.cursor_x;
}

fn styleOf(flags: u16) font_mod.Style {
    const bold = flags & cadex.CADEX_CELL_BOLD != 0;
    const italic = flags & cadex.CADEX_CELL_ITALIC != 0;
    return if (bold and italic) .bold_italic else if (bold) .bold else if (italic) .italic else .regular;
}

const Run = struct {
    glyphs: [max_run]u16 = undefined,
    advances: [max_run]f32 = undefined,
    len: usize = 0,
    x: f32 = 0,
    style: font_mod.Style = .regular,
    color: Color = Color.black,
};

fn flush(p: *gfx.Painter, font: *Font, run: *Run, baseline_y: f32) void {
    if (run.len == 0) return;
    p.glyphRun(font.faces[@intFromEnum(run.style)], font.metrics.em, run.glyphs[0..run.len], run.advances[0..run.len], .{ .x = run.x, .y = baseline_y }, run.color);
    run.len = 0;
}

fn drawGlyphs(p: *gfx.Painter, font: *Font, frame: *const cadex.cadex_terminal_frame, cells: []const cadex.cadex_terminal_cell, text: []const u8, ox: f32, oy: f32, cursor_at: ?usize, block: bool) void {
    const m = font.metrics;
    const cols: usize = frame.cols;
    var run: Run = .{};
    for (0..frame.rows) |row| {
        const top = oy + @as(f32, @floatFromInt(row)) * m.cell_height;
        const baseline = top + m.baseline;
        for (0..cols) |col| {
            const i = row * cols + col;
            const cell = cells[i];
            if (cell.text_len == 0 or cell.flags & cadex.CADEX_CELL_SPACER != 0) continue;
            const bytes = text[cell.text_offset..][0..cell.text_len];
            // Under a block cursor the glyph takes the background, to stay readable.
            const fg = if (block and cursor_at == i) frame.background else cell.fg;
            const faint = cell.flags & cadex.CADEX_CELL_FAINT != 0;
            const color = Color.rgb(fg).alpha(if (faint) 0.5 else 1);
            const style = styleOf(cell.flags);
            const wide = cell.flags & cadex.CADEX_CELL_WIDE != 0;
            const x = ox + @as(f32, @floatFromInt(col)) * m.cell_width;
            const span: f32 = if (wide) 2 else 1;
            const single = singleCodepoint(bytes);
            const g = if (single) |cp| font.glyph(cp, style) else null;
            const continues = run.len > 0 and run.style == style and colorEql(run.color, color) and
                @abs(run.x + sum(run.advances[0..run.len]) - x) < 0.5 and run.len < max_run;
            if (g == null) {
                flush(p, font, &run, baseline);
                // The layout picks a font that has it and centers it in its cells.
                const spec: gfx.FontSpec = .{ .family = font.family, .size = m.em, .weight = if (style == .bold or style == .bold_italic) .bold else .regular, .italic = style == .italic or style == .bold_italic };
                p.text(bytes, spec, .{ .x = x, .y = top, .w = m.cell_width * span, .h = m.cell_height }, color, .{ .@"align" = .center, .ellipsis = false });
                continue;
            }
            if (!continues) {
                flush(p, font, &run, baseline);
                run.x = x;
                run.style = style;
                run.color = color;
            }
            run.glyphs[run.len] = g.?;
            run.advances[run.len] = m.cell_width * span;
            run.len += 1;
        }
        flush(p, font, &run, baseline);
    }
}

fn sum(values: []const f32) f32 {
    var total: f32 = 0;
    for (values) |v| total += v;
    return total;
}

fn colorEql(a: Color, b: Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
}

/// The code point of a cell holding exactly one (most of them), else null.
fn singleCodepoint(bytes: []const u8) ?u21 {
    const len = std.unicode.utf8ByteSequenceLength(bytes[0]) catch return null;
    if (len != bytes.len) return null;
    const cp = std.unicode.utf8Decode(bytes) catch return null;
    // Emoji draw in color through the layout.
    if (cp >= 0x1F000) return null;
    return cp;
}

fn drawLines(p: *gfx.Painter, font: *Font, cells: []const cadex.cadex_terminal_cell, ox: f32, oy: f32, cols: usize, background: u32) void {
    _ = background;
    const m = font.metrics;
    for (cells, 0..) |cell, i| {
        const underline = (cell.flags >> cadex.CADEX_CELL_UNDERLINE_SHIFT) & 7;
        const strike = cell.flags & cadex.CADEX_CELL_STRIKETHROUGH != 0;
        if (underline == 0 and !strike) continue;
        const x = ox + @as(f32, @floatFromInt(i % cols)) * m.cell_width;
        const top = oy + @as(f32, @floatFromInt(i / cols)) * m.cell_height;
        const color = Color.rgb(cell.fg);
        const t = m.underline_thickness;
        if (underline != 0) {
            const y = top + @min(m.underline_offset, m.cell_height - t);
            switch (underline) {
                2 => {
                    p.fill(.{ .x = x, .y = y, .w = m.cell_width, .h = t }, color);
                    p.fill(.{ .x = x, .y = @max(y - 2 * t, top), .w = m.cell_width, .h = t }, color);
                },
                3 => {
                    // Curly: two half-cell strokes, up and down.
                    const half = m.cell_width / 2;
                    p.line(.{ .x = x, .y = y }, .{ .x = x + half, .y = y - t }, color, t);
                    p.line(.{ .x = x + half, .y = y - t }, .{ .x = x + m.cell_width, .y = y }, color, t);
                },
                4, 5 => {
                    const dash = if (underline == 4) t else m.cell_width / 3;
                    var dx: f32 = 0;
                    while (dx < m.cell_width) : (dx += dash * 2) p.fill(.{ .x = x + dx, .y = y, .w = @min(dash, m.cell_width - dx), .h = t }, color);
                },
                else => p.fill(.{ .x = x, .y = y, .w = m.cell_width, .h = t }, color),
            }
        }
        if (strike) p.fill(.{ .x = x, .y = top + m.strike_offset, .w = m.cell_width, .h = t }, color);
    }
}

fn underlineLink(p: *gfx.Painter, m: font_mod.Metrics, link: cadex.cadex_terminal_link, ox: f32, oy: f32, cols: usize, color: Color) void {
    var row: usize = link.start_row;
    while (row <= link.end_row) : (row += 1) {
        const from: usize = if (row == link.start_row) link.start_col else 0;
        const to: usize = if (row == link.end_row) link.end_col else cols - 1;
        const y = oy + @as(f32, @floatFromInt(row)) * m.cell_height + @min(m.underline_offset, m.cell_height - 1);
        p.fill(.{ .x = ox + @as(f32, @floatFromInt(from)) * m.cell_width, .y = y, .w = @as(f32, @floatFromInt(to - from + 1)) * m.cell_width, .h = m.underline_thickness }, color);
    }
}

test {
    std.testing.refAllDecls(@This());
}
