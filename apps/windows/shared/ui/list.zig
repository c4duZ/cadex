//! Scrolling and long lists that draw only the rows in view (the explorer
//! tree, search results, the palette, git's changes and log).

const std = @import("std");
const gfx = @import("gfx");
const context = @import("context.zig");

const Ui = context.Ui;
const Id = context.Id;

pub const Scroll = struct {
    offset: f32 = 0,
    /// Set while the scrollbar thumb is dragged: where it was grabbed.
    grab: ?f32 = null,

    pub fn clamp(self: *Scroll, content: f32, view: f32) void {
        self.offset = std.math.clamp(self.offset, 0, @max(content - view, 0));
    }

    /// Scrolls the least so that [top, top + h) shows in a view of `view`.
    pub fn reveal(self: *Scroll, top: f32, h: f32, view: f32) void {
        if (top < self.offset) self.offset = top;
        if (top + h > self.offset + view) self.offset = top + h - view;
    }
};

/// Pixels per wheel notch: three lines of 18 DIPs, as Windows scrolls.
fn notchPixels(ui: *Ui) f32 {
    return 3 * ui.px(18);
}

/// The wheel over `r` moves `scroll` within `content` pixels; draws a thin
/// scrollbar on the right when the content does not fit.
pub fn scrollArea(ui: *Ui, widget: Id, r: gfx.Rect, content: f32, scroll: *Scroll) void {
    if (ui.mouseOver(r) and ui.input.wheel != 0) {
        scroll.offset -= @as(f32, @floatFromInt(ui.input.wheel)) / 120 * notchPixels(ui);
        ui.input.wheel = 0;
    }
    scroll.clamp(content, r.h);
    if (content <= r.h) return;
    const bar_w = ui.px(6);
    const track: gfx.Rect = .{ .x = r.right() - bar_w - ui.px(2), .y = r.y + ui.px(2), .w = bar_w, .h = r.h - ui.px(4) };
    const thumb_h = @max(track.h * r.h / content, ui.px(24));
    const range = track.h - thumb_h;
    const max_offset = content - r.h;
    var thumb: gfx.Rect = .{ .x = track.x, .y = track.y + range * scroll.offset / max_offset, .w = bar_w, .h = thumb_h };
    const bar_id = context.child(widget, 0x5c);
    if (ui.mouseOver(thumb)) ui.next_hot = bar_id;
    if (ui.pressedOn(thumb, .left)) {
        ui.active = bar_id;
        scroll.grab = ui.input.mouse.y - thumb.y;
    }
    if (ui.active == bar_id and ui.input.down[0]) {
        if (scroll.grab) |g| {
            const y = std.math.clamp(ui.input.mouse.y - g - track.y, 0, range);
            scroll.offset = if (range > 0) y / range * max_offset else 0;
            thumb.y = track.y + y;
        }
    } else scroll.grab = null;
    const shown = ui.mouseOver(r) or ui.active == bar_id;
    ui.painter.fillRounded(thumb, bar_w / 2, ui.style.text.alpha(if (shown) 0.28 else 0.14));
}

/// The rows of a list that are in view: draw rows first..last at row(i).
pub const View = struct {
    area: gfx.Rect,
    row_h: f32,
    offset: f32,
    first: usize,
    last: usize,

    pub fn row(self: View, i: usize) gfx.Rect {
        return .{ .x = self.area.x, .y = self.area.y + @as(f32, @floatFromInt(i)) * self.row_h - self.offset, .w = self.area.w, .h = self.row_h };
    }
};

/// Starts a list of `count` rows of `row_h` in `r`, clipped; finish with end().
pub fn begin(ui: *Ui, widget: Id, r: gfx.Rect, count: usize, row_h: f32, scroll: *Scroll) View {
    const content = @as(f32, @floatFromInt(count)) * row_h;
    scrollArea(ui, widget, r, content, scroll);
    ui.painter.pushClip(r);
    const first: usize = @intFromFloat(@max(scroll.offset / row_h, 0));
    const shown: usize = @intFromFloat(@ceil(r.h / row_h) + 1);
    return .{ .area = r, .row_h = row_h, .offset = scroll.offset, .first = @min(first, count), .last = @min(first + shown, count) };
}

pub fn end(ui: *Ui) void {
    ui.painter.popClip();
}

/// Moves a list's selection with Up, Down, Page Up/Down, Home and End
/// (when those keys are unused); keeps it in view. The new index.
pub fn keyboardSelect(ui: *Ui, selected: usize, count: usize, view_rows: usize) usize {
    if (count == 0) return 0;
    const w = @import("win32");
    var i = @min(selected, count - 1);
    const none_mods: @import("input.zig").Mods = .{};
    if (ui.key(w.c.VK_DOWN, none_mods)) i = @min(i + 1, count - 1);
    if (ui.key(w.c.VK_UP, none_mods)) i -|= 1;
    if (ui.key(w.c.VK_NEXT, none_mods)) i = @min(i + view_rows, count - 1);
    if (ui.key(w.c.VK_PRIOR, none_mods)) i -|= view_rows;
    return i;
}

test "reveal scrolls the least" {
    var s: Scroll = .{};
    s.reveal(100, 20, 50);
    try std.testing.expectEqual(@as(f32, 70), s.offset);
    s.reveal(80, 20, 50);
    try std.testing.expectEqual(@as(f32, 70), s.offset);
    s.reveal(10, 20, 50);
    try std.testing.expectEqual(@as(f32, 10), s.offset);
}

test {
    @import("std").testing.refAllDecls(@This());
}
