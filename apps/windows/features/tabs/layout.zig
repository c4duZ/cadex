//! The panes of the active tab: placed by the tree, a 1-DIP divider that
//! takes the mouse 6 DIPs to each side and thickens under the pointer, and
//! the panes without the focus darker by tabs.unfocusedDim (docs/spec/tabs.md).

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const terminal = @import("terminal");
const pane_tree = @import("pane_tree.zig");
const controller = @import("controller.zig");

const Tabs = controller.Tabs;
const Node = pane_tree.Node;

/// The smallest share a pane keeps while a divider is dragged.
const min_ratio = 0.08;

pub const Layout = struct {
    /// The split being dragged (its node), while the button is down.
    dragging: ?*Node = null,
    /// The black shade over the panes without focus (tabs.unfocusedDim,
    /// plan 15): one value for light and dark themes, as on the Mac.
    unfocused_dim: f32 = 0.26,

    pub fn draw(self: *Layout, u: *ui.Ui, tabs: *Tabs, font: ?*terminal.Font, area: gfx.Rect) void {
        const t = tabs.active() orelse return;
        const gap = @max(1, u.px(1));
        var frames: std.ArrayList(pane_tree.Tree.Frame) = .empty;
        defer frames.deinit(u.gpa);
        t.tree.frames(area, gap, &frames);
        const several = frames.items.len > 1;
        for (frames.items) |f| {
            const pane = t.panes.get(f.pane) orelse continue;
            const focused = f.pane == t.focus;
            // A click anywhere in a pane gives it the focus.
            if (u.pressedOn(f.rect, .left) or u.pressedOn(f.rect, .right)) {
                if (!focused) tabs.focusPane(f.pane);
            }
            const has_keys = focused and (u.focus == focusIdOf(pane) or u.focus == ui.context.none);
            switch (pane) {
                .terminal => |v| if (font) |fnt| v.draw(u, fnt, f.rect, has_keys),
                .document => |d| d.draw(u, f.rect, has_keys),
            }
            if (focused and u.focus == ui.context.none) u.focus = focusIdOf(pane);
            if (several and !focused and self.unfocused_dim > 0) u.painter.fill(f.rect, gfx.Color.black.alpha(self.unfocused_dim));
        }
        self.dividers(u, t.tree.root, area, gap);
    }

    fn focusIdOf(pane: @import("tab.zig").Pane) ui.Id {
        return switch (pane) {
            .terminal => |v| v.id,
            .document => |d| d.focusId(),
        };
    }

    fn dividers(self: *Layout, u: *ui.Ui, node: *Node, rect: gfx.Rect, gap: f32) void {
        const s = switch (node.*) {
            .leaf => return,
            .split => |*s| s,
        };
        const parts = pane_tree.Tree.divide(rect, s.axis, s.ratio, gap);
        const horizontal = s.axis == .horizontal;
        const line: gfx.Rect = if (horizontal)
            .{ .x = parts[0].right(), .y = rect.y, .w = gap, .h = rect.h }
        else
            .{ .x = rect.x, .y = parts[0].bottom(), .w = rect.w, .h = gap };
        const reach = u.px(6);
        const grab = if (horizontal) line.inset(-reach, 0) else line.inset(0, -reach);
        const id = ui.child(ui.id("tabs.divider", 0), @intFromPtr(node));
        const over = u.mouseOver(grab);
        if (over) {
            u.next_hot = id;
            u.cursor = if (horizontal) .resize_we else .resize_ns;
        }
        if (over and u.input.pressed[0]) {
            self.dragging = node;
            u.active = id;
        }
        if (self.dragging == node) {
            if (u.input.down[0]) {
                const total = if (horizontal) rect.w - gap else rect.h - gap;
                const pos = if (horizontal) u.input.mouse.x - rect.x else u.input.mouse.y - rect.y;
                if (total > 0) s.ratio = std.math.clamp(pos / total, min_ratio, 1 - min_ratio);
                u.cursor = if (horizontal) .resize_we else .resize_ns;
            } else self.dragging = null;
        }
        const thick = over or self.dragging == node;
        const shown = if (thick) (if (horizontal) line.inset(-u.px(1), 0) else line.inset(0, -u.px(1))) else line;
        u.painter.fill(shown, if (thick) u.style.accent.alpha(0.7) else u.style.panel_border);
        self.dividers(u, s.a, parts[0], gap);
        self.dividers(u, s.b, parts[1], gap);
    }
};

test {
    @import("win32").refAllDeep(@This());
}
