//! The list of suggestions under the caret while writing a link (the Mac's
//! CompletionPopup): it never takes the keyboard, the note keeps typing,
//! and ↑ ↓ Enter Tab Esc steer it while it shows (session.zig passes them).

const std = @import("std");
const gfx = @import("gfx");
const w = @import("win32");
const ui_mod = @import("ui");
const icons = @import("icons");

const Ui = ui_mod.Ui;

pub const Item = struct {
    title: []const u8,
    /// Dimmed on the right: the folder, the anchor.
    detail: []const u8,
    /// What replaces the typed part.
    insert: []const u8,
    icon: u21 = icons.phosphor.file_md,
};

const max_shown = 8;

pub const Completion = struct {
    /// The items and their text live here until the next search.
    arena: std.heap.ArenaAllocator,
    items: []const Item = &.{},
    selected: usize = 0,
    /// The first row shown, to keep the selection in view.
    top: usize = 0,

    pub fn init(gpa: std.mem.Allocator) Completion {
        return .{ .arena = .init(gpa) };
    }

    pub fn deinit(self: *Completion) void {
        self.arena.deinit();
    }

    pub fn visible(self: *const Completion) bool {
        return self.items.len > 0;
    }

    /// An arena for the next list; the old one is gone.
    pub fn begin(self: *Completion) std.mem.Allocator {
        _ = self.arena.reset(.retain_capacity);
        self.items = &.{};
        self.selected = 0;
        self.top = 0;
        return self.arena.allocator();
    }

    pub fn hide(self: *Completion) void {
        _ = self.begin();
    }

    pub fn move(self: *Completion, delta: isize) void {
        if (self.items.len == 0) return;
        const n: isize = @intCast(self.items.len);
        self.selected = @intCast(@mod(@as(isize, @intCast(self.selected)) + delta, n));
        if (self.selected < self.top) self.top = self.selected;
        if (self.selected >= self.top + max_shown) self.top = self.selected + 1 - max_shown;
    }

    pub fn current(self: *const Completion) ?Item {
        if (self.selected >= self.items.len) return null;
        return self.items[self.selected];
    }

    /// The arrows, Enter, Tab and Esc while it shows; the item chosen, once.
    pub fn keys(self: *Completion, u: *Ui) ?Item {
        if (!self.visible()) return null;
        if (u.key(w.c.VK_DOWN, .{})) self.move(1);
        if (u.key(w.c.VK_UP, .{})) self.move(-1);
        if (u.key(w.c.VK_ESCAPE, .{})) {
            self.hide();
            return null;
        }
        if (u.key(w.c.VK_RETURN, .{}) or u.key(w.c.VK_TAB, .{})) return self.current();
        return null;
    }

    /// Draws below `caret` (above when there is no room); a clicked item, once.
    pub fn draw(self: *Completion, u: *Ui, id: ui_mod.Id, caret: gfx.Rect, area: gfx.Rect) ?Item {
        if (!self.visible()) return null;
        const row_h = u.px(24);
        const shown = @min(self.items.len - self.top, max_shown);
        const pad = u.px(4);
        var box: gfx.Rect = .{ .x = caret.x, .y = caret.bottom() + u.px(2), .w = @min(u.px(360), area.w), .h = @as(f32, @floatFromInt(shown)) * row_h + 2 * pad };
        if (box.right() > area.right()) box.x = @max(area.right() - box.w, area.x);
        if (box.bottom() > area.bottom()) box.y = @max(caret.y - box.h - u.px(2), area.y);
        u.beginOverlay(box);
        defer u.endOverlay();
        u.painter.fillRounded(box.inset(-1, -1), u.px(7), u.style.panel_border);
        u.painter.fillRounded(box, u.px(7), u.style.panel);
        var chosen: ?Item = null;
        for (self.top..self.top + shown) |i| {
            const item = self.items[i];
            const row: gfx.Rect = .{ .x = box.x + pad, .y = box.y + pad + @as(f32, @floatFromInt(i - self.top)) * row_h, .w = box.w - 2 * pad, .h = row_h };
            if (i == self.selected) u.painter.fillRounded(row, u.px(5), u.style.selection());
            if (u.clickable(ui_mod.child(id, i), row)) chosen = item;
            var content = row.inset(u.px(6), 0);
            u.painter.icon(item.icon, u.px(13), content.takeLeft(u.px(20)), u.style.secondary_text);
            const title_w = @min(u.painter.measure(item.title, u.style.ui()) + u.px(10), content.w * 0.6);
            u.painter.text(item.title, u.style.ui(), content.takeLeft(title_w), u.style.text, .{});
            u.painter.text(item.detail, u.style.small(), content, u.style.secondary_text, .{});
        }
        return chosen;
    }
};

test "moving wraps and keeps the selection in view" {
    var c = Completion.init(std.testing.allocator);
    defer c.deinit();
    const a = c.begin();
    const list = try a.alloc(Item, 10);
    for (list) |*it| it.* = .{ .title = "t", .detail = "", .insert = "" };
    c.items = list;
    c.move(-1);
    try std.testing.expectEqual(@as(usize, 9), c.selected);
    try std.testing.expectEqual(@as(usize, 2), c.top);
    c.move(1);
    try std.testing.expectEqual(@as(usize, 0), c.selected);
    try std.testing.expectEqual(@as(usize, 0), c.top);
}

test {
    @import("win32").refAllDeep(@This());
}
