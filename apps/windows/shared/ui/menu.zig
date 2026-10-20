//! A popup menu (right click, the "+" of the tabs) and a modal question
//! (close with a program running, discard changes). Both draw in the
//! overlay, so the window below sees no mouse while they are open.

const std = @import("std");
const gfx = @import("gfx");
const w = @import("win32");
const context = @import("context.zig");

const Ui = context.Ui;
const Id = context.Id;

pub const Item = struct {
    label: []const u8 = "",
    /// "Ctrl+Shift+T", drawn on the right.
    shortcut: []const u8 = "",
    icon: ?u21 = null,
    enabled: bool = true,
    separator: bool = false,
};

/// Where an open menu is and which is open; one at a time per window.
pub const Menu = struct {
    owner: Id = context.none,
    at: gfx.Point = .{},
    hovered: ?usize = null,

    pub fn open(self: *Menu, owner: Id, at: gfx.Point) void {
        self.* = .{ .owner = owner, .at = at };
    }

    pub fn isOpen(self: *const Menu, owner: Id) bool {
        return self.owner == owner;
    }

    pub fn close(self: *Menu) void {
        self.owner = context.none;
    }
};

/// Draws the open menu of `owner` with `items`; the chosen index, once.
/// A click outside or Escape closes it.
pub fn show(ui: *Ui, menu: *Menu, owner: Id, items: []const Item) ?usize {
    if (!menu.isOpen(owner)) return null;
    const row_h = ui.px(28);
    const sep_h = ui.px(9);
    const pad = ui.px(5);
    var width: f32 = ui.px(180);
    var height: f32 = 2 * pad;
    for (items) |item| {
        if (item.separator) {
            height += sep_h;
            continue;
        }
        const label_w = ui.painter.measure(item.label, ui.style.ui()) + ui.painter.measure(item.shortcut, ui.style.small());
        width = @max(width, label_w + ui.px(if (item.icon != null) 84 else 60));
        height += row_h;
    }
    var box: gfx.Rect = .{ .x = menu.at.x, .y = menu.at.y, .w = width, .h = height };
    // Keep it inside the window.
    if (box.right() > ui.size.x) box.x = @max(ui.size.x - box.w - pad, 0);
    if (box.bottom() > ui.size.y) box.y = @max(menu.at.y - box.h, 0);

    ui.beginOverlay(.{ .x = 0, .y = 0, .w = ui.size.x, .h = ui.size.y });
    defer ui.endOverlay();
    ui.painter.fillRounded(box.inset(-1, -1), ui.px(8), ui.style.panel_border);
    ui.painter.fillRounded(box, ui.px(8), ui.style.panel);

    var chosen: ?usize = null;
    var y = box.y + pad;
    for (items, 0..) |item, i| {
        if (item.separator) {
            ui.painter.fill(.{ .x = box.x + pad, .y = y + sep_h / 2, .w = box.w - 2 * pad, .h = @max(1, ui.px(1)) }, ui.style.separator());
            y += sep_h;
            continue;
        }
        const row: gfx.Rect = .{ .x = box.x + pad, .y = y, .w = box.w - 2 * pad, .h = row_h };
        y += row_h;
        const over = ui.mouseOver(row);
        if (over and item.enabled) {
            ui.painter.fillRounded(row, ui.px(5), ui.style.hover());
            if (ui.input.released[0]) chosen = i;
        }
        var content = row.inset(ui.px(8), 0);
        const fg = if (item.enabled) ui.style.text else ui.style.secondary_text.alpha(0.6);
        if (item.icon) |cp| ui.painter.icon(cp, ui.px(15), content.takeLeft(ui.px(24)), fg);
        if (item.shortcut.len > 0) {
            const sw = ui.painter.measure(item.shortcut, ui.style.small());
            ui.painter.text(item.shortcut, ui.style.small(), content.takeRight(sw + ui.px(4)), ui.style.secondary_text, .{ .@"align" = .trailing });
        }
        ui.painter.text(item.label, ui.style.ui(), content, fg, .{});
    }
    const outside = (ui.input.pressed[0] or ui.input.pressed[1]) and !box.contains(ui.input.mouse);
    if (chosen != null or outside or ui.key(w.c.VK_ESCAPE, .{})) menu.close();
    return chosen;
}

pub const Question = struct {
    title: []const u8,
    message: []const u8 = "",
    /// The first is the default (Enter); the last answers Escape.
    buttons: []const []const u8,
};

/// A modal question centered on the window; the button chosen, once.
pub fn ask(ui: *Ui, question: Question) ?usize {
    const full: gfx.Rect = .{ .x = 0, .y = 0, .w = ui.size.x, .h = ui.size.y };
    ui.beginOverlay(full);
    defer ui.endOverlay();
    ui.painter.fill(full, gfx.Color.black.alpha(0.35));
    const box_w = @min(ui.px(420), ui.size.x - ui.px(32));
    var box: gfx.Rect = .{ .x = (ui.size.x - box_w) / 2, .y = ui.size.y * 0.3, .w = box_w, .h = ui.px(if (question.message.len > 0) 150 else 120) };
    ui.painter.fillRounded(box.inset(-1, -1), ui.px(10), ui.style.panel_border);
    ui.painter.fillRounded(box, ui.px(10), ui.style.panel);
    var inner = box.inset(ui.px(20), ui.px(18));
    ui.painter.text(question.title, ui.style.bold(), inner.takeTop(ui.px(22)), ui.style.text, .{});
    if (question.message.len > 0) ui.painter.text(question.message, ui.style.ui(), inner.takeTop(ui.px(36)), ui.style.secondary_text, .{});
    var row = inner.takeBottom(ui.px(32));
    var chosen: ?usize = null;
    var i = question.buttons.len;
    while (i > 0) {
        i -= 1;
        const title = question.buttons[i];
        const bw = ui.painter.measure(title, ui.style.ui()) + ui.px(28);
        const r = row.takeRight(bw);
        _ = row.takeRight(ui.px(8));
        if (@import("widgets.zig").button(ui, context.child(context.id("question", 0), i), r, title, .{ .primary = i == 0 })) chosen = i;
    }
    if (ui.key(w.c.VK_RETURN, .{})) chosen = 0;
    if (ui.key(w.c.VK_ESCAPE, .{})) chosen = question.buttons.len - 1;
    return chosen;
}

test {
    @import("std").testing.refAllDecls(@This());
}
