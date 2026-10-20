//! The tab bar, in the window's title bar (docs/spec/tabs.md): tabs of equal
//! width (up to 220 DIPs, shrinking to fit), each with the icon of what it
//! shows; the active one with a stronger background and a line in the
//! theme's accent; × on the active and the hovered; middle click closes,
//! double click renames, dragging reorders; "+" after them.

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const icons = @import("icons");
const controller = @import("controller.zig");

const Tabs = controller.Tabs;

pub const Bar = struct {
    renaming: ?u32 = null,
    rename_text: ui.TextBuffer = .{},
    rename_scroll: ui.text_field.Scroll = .{},
    /// A tab being dragged: its id and where it was grabbed.
    dragging: ?u32 = null,
    drag_from_x: f32 = 0,

    pub fn deinit(self: *Bar, gpa: std.mem.Allocator) void {
        self.rename_text.deinit(gpa);
    }

    pub fn startRename(self: *Bar, u: *ui.Ui, tabs: *Tabs) void {
        const t = tabs.active() orelse return;
        var arena: std.heap.ArenaAllocator = .init(u.gpa);
        defer arena.deinit();
        self.rename_text.set(u.gpa, tabs.title(t, arena.allocator())) catch return;
        self.rename_text.selectAll();
        self.renaming = t.id;
        u.focus = ui.id("tabs.rename", 0);
    }

    pub const Result = struct {
        /// "+" was clicked, at this point (the app opens the menu there).
        plus_at: ?gfx.Point = null,
    };

    /// Draws the tabs in `area`; the width taken, and what was clicked.
    pub fn draw(self: *Bar, u: *ui.Ui, tabs: *Tabs, area: gfx.Rect) Result {
        var result: Result = .{};
        const order = tabs.list.order.items;
        const plus_w = u.px(32);
        const gap = u.px(2);
        const n: f32 = @floatFromInt(@max(order.len, 1));
        const width = @min(u.px(220), (area.w - plus_w - gap * n) / n);
        var arena: std.heap.ArenaAllocator = .init(u.gpa);
        defer arena.deinit();
        var x = area.x;
        for (order, 0..) |id, i| {
            const t = tabs.tabs.get(id) orelse continue;
            const r: gfx.Rect = .{ .x = x, .y = area.y + u.px(4), .w = width, .h = area.h - u.px(4) };
            x += width + gap;
            self.drawTab(u, tabs, t, r, i, arena.allocator());
        }
        const plus: gfx.Rect = .{ .x = x, .y = area.y + u.px(6), .w = plus_w - u.px(4), .h = area.h - u.px(10) };
        if (ui.widgets.iconButton(u, ui.id("tabs.plus", 0), plus, icons.phosphor.plus, .{ .icon_size = 15 })) result.plus_at = .{ .x = plus.x, .y = plus.bottom() };
        if (self.dragging != null and !u.input.down[0]) self.dragging = null;
        return result;
    }

    fn drawTab(self: *Bar, u: *ui.Ui, tabs: *Tabs, t: *@import("tab.zig").Tab, r: gfx.Rect, index: usize, arena: std.mem.Allocator) void {
        const tab_id = ui.child(ui.id("tabs.tab", 0), t.id);
        const is_active = tabs.list.active == t.id;
        const over = u.mouseOver(r);
        if (over) u.next_hot = tab_id;
        if (u.pressedOn(r, .left)) {
            if (u.input.clicks == 2) return self.startRename(u, tabs);
            tabs.select(t.id);
            self.dragging = t.id;
            self.drag_from_x = u.input.mouse.x;
        }
        if (u.pressedOn(r, .middle)) return tabs.requestClose(.{ .tab = t.id });
        // Dragging past half a tab moves it there.
        if (self.dragging == t.id and u.input.down[0]) {
            const dx = u.input.mouse.x - self.drag_from_x;
            if (@abs(dx) > r.w / 2) {
                const step: i32 = if (dx > 0) 1 else -1;
                const target: usize = @intCast(std.math.clamp(@as(i32, @intCast(index)) + step, 0, @as(i32, @intCast(tabs.list.order.items.len)) - 1));
                tabs.list.move(t.id, target);
                self.drag_from_x += @as(f32, @floatFromInt(step)) * r.w;
            }
        }
        const style = u.style;
        const background = if (is_active) style.tab_active else if (over) style.hover() else style.text.alpha(0.04);
        u.painter.fillRounded(r, u.px(7), background);
        if (is_active) u.painter.fill(.{ .x = r.x + u.px(8), .y = r.bottom() - u.px(2), .w = r.w - u.px(16), .h = u.px(2) }, style.accent);

        var content = r.inset(u.px(10), 0);
        const pane = t.focused();
        const icon: u21 = switch (pane) {
            .terminal => icons.phosphor.terminal_window,
            .document => |d| d.icon(),
        };
        const icon_color = switch (pane) {
            .terminal => null,
            .document => |d| d.iconColor(),
        };
        const icon_rect = content.takeLeft(u.px(20));
        // A file's tab shows its Material drawing, as the tree does.
        const material = switch (pane) {
            .terminal => false,
            .document => |d| isFile(d.identity()) and icons.material.drawNamed(u.painter, std.fs.path.basenameWindows(d.identity()), false, @round(u.px(15)), icon_rect),
        };
        if (!material) u.painter.icon(icon, u.px(14), icon_rect, icon_color orelse style.secondary_text);
        if (is_active or over) {
            const x_rect = content.takeRight(u.px(20));
            const box: gfx.Rect = .{ .x = x_rect.x, .y = x_rect.center().y - u.px(9), .w = u.px(18), .h = u.px(18) };
            if (ui.widgets.iconButton(u, ui.child(tab_id, 1), box, icons.phosphor.x, .{ .icon_size = 11, .radius = 4 })) tabs.requestClose(.{ .tab = t.id });
        }
        if (self.renaming == t.id) {
            const field_id = ui.id("tabs.rename", 0);
            const res = ui.text_field.textField(u, field_id, content.inset(0, u.px(4)), &self.rename_text, &self.rename_scroll, .{ .autofocus = true });
            if (res.submitted) {
                t.setName(self.rename_text.text());
                self.renaming = null;
                tabs.host.on_change(tabs.host.context);
            }
            if (res.cancelled or (u.focus != field_id)) self.renaming = null;
            return;
        }
        var title = tabs.title(t, arena);
        if (t.unsaved()) title = std.fmt.allocPrint(arena, "● {s}", .{title}) catch title;
        u.painter.text(title, style.ui(), content, if (is_active) style.text else style.secondary_text, .{});
    }
};

/// A document that is a file on disk ("C:\\x\\a.zig"), not "history:..." or a URL.
fn isFile(identity: []const u8) bool {
    return (identity.len > 2 and identity[1] == ':') or std.mem.startsWith(u8, identity, "\\\\");
}

test {
    @import("win32").refAllDeep(@This());
}
