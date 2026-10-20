//! The mouse and the keys of a View (view.zig), as any Windows text box:
//! click, Shift+click, double click a word, triple click a line, drag with
//! autoscroll; arrows, Ctrl for words, Home and End, Page Up and Down;
//! and, when editing, typing, Backspace, Delete, Enter keeping the indent,
//! Tab, Ctrl+Z, Ctrl+Y, Ctrl+X, Ctrl+V. Ctrl+C, Ctrl+A and Ctrl+F work
//! read-only too. The app's shortcuts (Ctrl+Shift+…) never get here.

const std = @import("std");
const gfx = @import("gfx");
const w = @import("win32");
const ui_mod = @import("ui");
const buffer_mod = @import("buffer.zig");
const wrap = @import("wrap.zig");
const View = @import("view.zig").View;
const Row = @import("rows.zig").Row;
const view_draw = @import("view_draw.zig");

const Ui = ui_mod.Ui;
const c = w.c;

/// The byte under a point of the text area.
pub fn hit(view: *const View, at: gfx.Point) usize {
    const n = view.rows.count();
    if (n == 0) return 0;
    const m = view.metrics;
    const y = at.y - m.text.y + view.scroll.offset;
    if (y < 0) return 0;
    const i: usize = @intFromFloat(y / m.row_h);
    if (i >= n) return view.text().len;
    const col = @max((at.x - m.text.x) / m.cell_w, 0);
    return byteOnRow(view, view.rows.items.items[i], col);
}

/// The byte nearest column `col` of `row`; never past a wrapped row's end
/// (that is where the next row starts).
fn byteOnRow(view: *const View, row: Row, col: f32) usize {
    const at = wrap.byteAt(view.text(), row.start, row.end, col);
    if (!row.last and at >= row.end and row.end > row.start) return buffer_mod.prevBoundary(view.text(), row.end);
    return at;
}

pub fn mouse(view: *View, u: *Ui, area: gfx.Rect) void {
    const m = view.metrics;
    if (u.mouseOver(m.text)) u.cursor = .ibeam;
    const b = &view.buffer;
    if (u.pressedOn(m.gutter, .left)) {
        u.focus = view.id;
        const at = hit(view, .{ .x = m.text.x, .y = u.input.mouse.y });
        const line = b.lineOf(at);
        if (view_draw.onArrow(view, u, u.input.mouse.x) and view.folding.regionAt(line) != null) {
            view.folding.toggle(view.gpa, line) catch {};
        } else {
            b.selectLineAt(at);
        }
        return;
    }
    const text_area: gfx.Rect = .{ .x = m.text.x, .y = area.y, .w = area.right() - m.text.x - u.px(12), .h = area.h };
    if (u.pressedOn(text_area, .left)) {
        u.focus = view.id;
        u.active = view.id;
        view.goal_col = null;
        const at = hit(view, u.input.mouse);
        if (u.input.mods.ctrl) if (view.hooks) |h| if (h.ctrl_click) |f| if (f(h.context, view, at)) {
            u.active = ui_mod.context.none;
            return;
        };
        switch (u.input.clicks) {
            2 => b.selectWordAt(at),
            3 => b.selectLineAt(at),
            else => b.place(at, u.input.mods.shift),
        }
        return;
    }
    if (u.active == view.id and u.input.down[0] and u.input.clicks == 1) {
        b.place(hit(view, u.input.mouse), true);
        // Dragging past the top or the bottom scrolls, a row per frame.
        if (u.input.mouse.y < area.y) view.scroll.offset -= m.row_h;
        if (u.input.mouse.y > area.bottom()) view.scroll.offset += m.row_h;
        if (u.input.mouse.y < area.y or u.input.mouse.y > area.bottom()) u.requestFrame(30);
    }
}

/// Up or down `delta` rows, keeping the column.
fn vertical(view: *View, delta: isize, extend: bool) void {
    const b = &view.buffer;
    const n = view.rows.count();
    if (n == 0) return;
    const i = view.rows.rowOf(b.caret);
    const row = view.rows.items.items[i];
    const col = view.goal_col orelse wrap.columnOf(view.text(), row.start, b.caret);
    const target = @as(isize, @intCast(i)) + delta;
    const goal = col;
    if (target < 0) {
        b.place(0, extend);
    } else if (target >= @as(isize, @intCast(n))) {
        b.place(view.text().len, extend);
    } else {
        b.place(byteOnRow(view, view.rows.items.items[@intCast(target)], @floatFromInt(col)), extend);
    }
    view.goal_col = goal;
    view.reveal_caret = true;
}

pub fn keys(view: *View, u: *Ui) void {
    if (view.hooks) |h| if (h.keys) |f| f(h.context, u, view);
    for (u.input.keys.items) |*k| {
        if (k.used) continue;
        k.used = true;
        if (!key(view, u, k.vk, k.mods)) k.used = false;
    }
    if (u.input.text.items.len > 0 and view.editable) {
        view.buffer.insert(u.input.text.items, .typing) catch {};
        u.input.text.clearRetainingCapacity();
        view.goal_col = null;
    }
}

/// One key; false when the view has nothing to do with it.
fn key(view: *View, u: *Ui, vk: u16, mods: ui_mod.Mods) bool {
    const b = &view.buffer;
    const shift = mods.shift;
    const ctrl = mods.ctrl and !mods.alt;
    const rows: isize = @intCast(view.metrics.view_rows);
    if (mods.alt) return false;
    switch (vk) {
        c.VK_UP => if (ctrl) scrollRows(view, -1) else vertical(view, -1, shift),
        c.VK_DOWN => if (ctrl) scrollRows(view, 1) else vertical(view, 1, shift),
        c.VK_PRIOR => vertical(view, -rows, shift),
        c.VK_NEXT => vertical(view, rows, shift),
        c.VK_LEFT, c.VK_RIGHT, c.VK_HOME, c.VK_END => {
            const motion: buffer_mod.Motion = switch (vk) {
                c.VK_LEFT => if (ctrl) .word_left else .left,
                c.VK_RIGHT => if (ctrl) .word_right else .right,
                c.VK_HOME => if (ctrl) .doc_start else .line_start,
                else => if (ctrl) .doc_end else .line_end,
            };
            b.move(motion, shift);
            view.goal_col = null;
            view.reveal_caret = true;
        },
        c.VK_ESCAPE => if (view.find.open) view.find.hide(u, view) else return false,
        'A' => if (ctrl and !shift) b.selectAll() else return false,
        'C' => if (ctrl and !shift) copy(view, u) else return false,
        'F' => if (ctrl and !shift) view.find.show(u, view) else return false,
        else => return view.editable and editKey(view, u, vk, shift, ctrl),
    }
    return true;
}

fn editKey(view: *View, u: *Ui, vk: u16, shift: bool, ctrl: bool) bool {
    const b = &view.buffer;
    view.goal_col = null;
    switch (vk) {
        c.VK_BACK => b.backspace(ctrl) catch {},
        c.VK_DELETE => b.delete(ctrl) catch {},
        c.VK_RETURN => if (!ctrl) newline(view) else return false,
        c.VK_TAB => if (ctrl) return false else if (shift) outdent(view) else b.insert(view.indent, .other) catch {},
        'X' => if (ctrl and !shift) cut(view, u) else return false,
        'V' => if (ctrl and !shift) paste(view, u) else return false,
        'Z' => if (ctrl and !shift) {
            _ = b.undo() catch false;
        } else return false,
        'Y' => if (ctrl and !shift) {
            _ = b.redo() catch false;
        } else return false,
        else => return false,
    }
    view.reveal_caret = true;
    return true;
}

fn scrollRows(view: *View, delta: f32) void {
    view.scroll.offset += delta * view.metrics.row_h;
}

/// Enter keeps the indent of the line it breaks.
pub fn newline(view: *View) void {
    const b = &view.buffer;
    const line_start = b.lineStart(b.lineOf(b.selection().start));
    var end = line_start;
    while (end < b.text().len and (b.text()[end] == ' ' or b.text()[end] == '\t')) end += 1;
    var value: std.ArrayList(u8) = .empty;
    defer value.deinit(view.gpa);
    value.appendSlice(view.gpa, "\n") catch return;
    value.appendSlice(view.gpa, b.text()[line_start..@min(end, b.selection().start)]) catch return;
    b.insert(value.items, .other) catch {};
}

/// Shift+Tab takes one indent off the caret's line.
fn outdent(view: *View) void {
    const b = &view.buffer;
    const start = b.lineStart(b.lineOf(b.caret));
    const t = b.text();
    var n: usize = 0;
    if (start < t.len and t[start] == '\t') n = 1 else while (n < view.indent.len and start + n < t.len and t[start + n] == ' ') n += 1;
    if (n == 0) return;
    const caret = b.caret;
    b.replace(start, start + n, "", .other) catch return;
    b.place(if (caret >= start + n) caret - n else start, false);
}

pub fn copy(view: *View, u: *Ui) void {
    if (view.buffer.hasSelection()) ui_mod.clipboard.writeText(view.gpa, u.hwnd, view.buffer.selected());
}

pub fn cut(view: *View, u: *Ui) void {
    if (!view.editable or !view.buffer.hasSelection()) return;
    copy(view, u);
    view.buffer.backspace(false) catch {};
}

pub fn paste(view: *View, u: *Ui) void {
    if (!view.editable) return;
    const pasted = ui_mod.clipboard.readText(view.gpa, u.hwnd) orelse return;
    defer view.gpa.free(pasted);
    view.buffer.insert(pasted, .other) catch {};
    view.reveal_caret = true;
}

test {
    @import("win32").refAllDeep(@This());
}
