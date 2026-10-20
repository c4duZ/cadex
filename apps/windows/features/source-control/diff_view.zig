//! How a diff document draws: two columns with line numbers and the marked
//! lines tinted, scrolling together in proportion (the Mac's follow()), or
//! the patch with + green, - red and @@ blue. Only the lines in view.

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const diff_lines = @import("diff_lines.zig");
const DiffDocument = @import("diff_document.zig").DiffDocument;

const Rect = gfx.Rect;
const Color = gfx.Color;

const red = Color.rgb(0xff453a);
const green = Color.rgb(0x30d158);
const blue = Color.rgb(0x0a84ff);

pub const State = struct {
    left: ui.list.Scroll = .{},
    right: ui.list.Scroll = .{},
    patch: ui.list.Scroll = .{},
    /// Where each side was after the last frame: the one that moved leads.
    last_left: f32 = 0,
    last_right: f32 = 0,
};

pub fn draw(doc: *DiffDocument, u: *ui.Ui, area: Rect, focused: bool) void {
    _ = focused;
    u.painter.fill(area, u.style.panel);
    const base = ui.id("scm.diff-view", 0);
    const id = ui.child(base, @intFromPtr(doc));
    switch (doc.state) {
        .loading => return message(u, area, "Carregando o diff…"),
        .failed => return message(u, area, "Não foi possível ler o diff"),
        .ready => {},
    }
    const d = doc.diff orelse return;
    if (d.binary) return message(u, area, "Arquivo binário, sem diff");
    if (d.too_large) {
        message(u, area, "Arquivo grande demais para o diff");
        const title = "Abrir o arquivo";
        const bw = u.painter.measure(title, u.style.ui()) + u.px(28);
        const r: Rect = .{ .x = area.x + (area.w - bw) / 2, .y = area.y + area.h * 0.4 + u.px(20), .w = bw, .h = u.px(30) };
        u.painter.fillRounded(r, u.px(6), u.style.field);
        if (ui.widgets.button(u, ui.child(id, 9), r, title, .{})) doc.openFile();
        return;
    }
    if (!doc.side_by_side) {
        if (d.patch.len == 0) return message(u, area, "Sem diferenças");
        return patchColumn(u, ui.child(id, 3), area, d.patch, doc.patch_lines, &doc.view.patch);
    }
    var left = area;
    left.w = @floor((area.w - 1) / 2);
    var right = area;
    right.x = left.right() + 1;
    right.w = area.right() - right.x;
    u.painter.fill(.{ .x = left.right(), .y = area.y, .w = 1, .h = area.h }, u.style.separator());
    const marks = doc.marks;
    column(u, ui.child(id, 1), left, d.before, doc.before_lines, if (marks) |m| m.removed else &.{}, red, &doc.view.left);
    column(u, ui.child(id, 2), right, d.after, doc.after_lines, if (marks) |m| m.added else &.{}, green, &doc.view.right);
    follow(u, &doc.view, left.h, doc.before_lines.len, doc.after_lines.len);
}

fn message(u: *ui.Ui, area: Rect, text: []const u8) void {
    const line: Rect = .{ .x = area.x, .y = area.y + area.h * 0.4 - u.px(11), .w = area.w, .h = u.px(22) };
    u.painter.text(text, u.style.ui(), line, u.style.secondary_text, .{ .@"align" = .center });
}

fn rowHeight(u: *ui.Ui) f32 {
    return u.px(18);
}

/// One side moved: the other goes to the same place, in proportion.
fn follow(u: *ui.Ui, s: *State, view_h: f32, left_lines: usize, right_lines: usize) void {
    const row_h = rowHeight(u);
    const left_max = @max(@as(f32, @floatFromInt(left_lines + 1)) * row_h - view_h, 0);
    const right_max = @max(@as(f32, @floatFromInt(right_lines + 1)) * row_h - view_h, 0);
    if (s.left.offset != s.last_left and left_max > 0) {
        s.right.offset = s.left.offset / left_max * right_max;
    } else if (s.right.offset != s.last_right and right_max > 0) {
        s.left.offset = s.right.offset / right_max * left_max;
    }
    s.last_left = s.left.offset;
    s.last_right = s.right.offset;
}

/// The width of the line numbers for a text of `lines` lines.
fn gutterWidth(u: *ui.Ui, lines: usize) f32 {
    var buf: [16]u8 = undefined;
    const widest = std.fmt.bufPrint(&buf, "{d}", .{@max(lines, 99)}) catch "999";
    return u.painter.measure(widest, u.style.mono(11)) + u.px(16);
}

fn column(u: *ui.Ui, widget: ui.Id, r: Rect, text: []const u8, starts: []const u32, marked: []const bool, tint: Color, scroll: *ui.list.Scroll) void {
    const row_h = rowHeight(u);
    // A line of room under the last one, as an editor leaves.
    const view = ui.list.begin(u, widget, r, starts.len + 1, row_h, scroll);
    defer ui.list.end(u);
    const gutter = gutterWidth(u, starts.len);
    const spec = u.style.mono(12);
    var num_buf: [16]u8 = undefined;
    for (view.first..@min(view.last, starts.len)) |i| {
        const row = view.row(i);
        if (i < marked.len and marked[i]) u.painter.fill(row, tint.alpha(0.18));
        const number = std.fmt.bufPrint(&num_buf, "{d}", .{i + 1}) catch "";
        u.painter.text(number, u.style.mono(11), .{ .x = row.x, .y = row.y, .w = gutter - u.px(8), .h = row.h }, u.style.secondary_text.alpha(0.7), .{ .@"align" = .trailing, .ellipsis = false });
        const content: Rect = .{ .x = row.x + gutter, .y = row.y, .w = 100_000, .h = row.h };
        u.painter.text(diff_lines.line(text, starts, i), spec, content, u.style.text, .{ .ellipsis = false });
    }
}

fn patchColumn(u: *ui.Ui, widget: ui.Id, r: Rect, patch: []const u8, starts: []const u32, scroll: *ui.list.Scroll) void {
    const row_h = rowHeight(u);
    const view = ui.list.begin(u, widget, r, starts.len + 1, row_h, scroll);
    defer ui.list.end(u);
    const spec = u.style.mono(12);
    for (view.first..@min(view.last, starts.len)) |i| {
        const row = view.row(i);
        const l = diff_lines.line(patch, starts, i);
        const color = lineColor(u, l);
        if (l.len > 0 and (l[0] == '+' or l[0] == '-') and !isFileHeader(l)) u.painter.fill(row, color.alpha(0.12));
        const content: Rect = .{ .x = row.x + u.px(10), .y = row.y, .w = 100_000, .h = row.h };
        u.painter.text(l, spec, content, color, .{ .ellipsis = false });
    }
}

fn isFileHeader(l: []const u8) bool {
    return std.mem.startsWith(u8, l, "+++ ") or std.mem.startsWith(u8, l, "--- ");
}

fn lineColor(u: *ui.Ui, l: []const u8) Color {
    if (isFileHeader(l)) return u.style.secondary_text;
    if (std.mem.startsWith(u8, l, "@@")) return blue;
    if (l.len > 0 and l[0] == '+') return green;
    if (l.len > 0 and l[0] == '-') return red;
    return u.style.text;
}

test {
    @import("win32").refAllDeep(@This());
}
