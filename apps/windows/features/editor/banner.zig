//! A strip at the top of an editor pane for notes that need attention: a
//! big file shown in part, a change on disk, a failed save (the Mac's
//! EditorBanner), with up to two buttons; and the message that takes the
//! whole pane instead of the text (a binary file, an error).

const std = @import("std");
const gfx = @import("gfx");
const ui_mod = @import("ui");

const Ui = ui_mod.Ui;

pub const Action = enum { reload, keep_mine };

pub const Banner = struct {
    /// Static Portuguese text; null hides the strip.
    message: ?[]const u8 = null,
    actions: []const Action = &.{},

    pub fn show(self: *Banner, note: []const u8, actions: []const Action) void {
        self.* = .{ .message = note, .actions = actions };
    }

    pub fn hide(self: *Banner) void {
        self.* = .{};
    }

    fn title(action: Action) []const u8 {
        return switch (action) {
            .reload => "Recarregar",
            .keep_mine => "Manter o meu",
        };
    }

    /// Takes its strip off the top of `area` and draws it; the button
    /// pressed, once.
    pub fn draw(self: *Banner, u: *Ui, id: ui_mod.Id, area: *gfx.Rect) ?Action {
        const note = self.message orelse return null;
        const strip = area.takeTop(u.px(30));
        u.painter.fill(strip, gfx.Color.rgb(0xffcc00).alpha(0.18));
        var inner = strip.inset(u.px(10), u.px(3));
        var chosen: ?Action = null;
        var i = self.actions.len;
        while (i > 0) {
            i -= 1;
            const name = title(self.actions[i]);
            const r = inner.takeRight(u.painter.measure(name, u.style.small()) + u.px(20));
            _ = inner.takeRight(u.px(6));
            if (ui_mod.widgets.button(u, ui_mod.child(id, 0xba + i), r, name, .{ .selected = true })) chosen = self.actions[i];
        }
        u.painter.text(note, u.style.small(), inner, u.style.text, .{});
        return chosen;
    }
};

/// The pane instead of the text: the message and, optionally, a button.
/// True when the button was pressed.
pub fn fullMessage(u: *Ui, id: ui_mod.Id, area: gfx.Rect, text: []const u8, button: ?[]const u8) bool {
    const center = area.center();
    u.painter.text(text, u.style.font(14), .{ .x = area.x, .y = center.y - u.px(30), .w = area.w, .h = u.px(24) }, u.style.secondary_text, .{ .@"align" = .center });
    const name = button orelse return false;
    const bw = u.painter.measure(name, u.style.ui()) + u.px(28);
    return ui_mod.widgets.button(u, ui_mod.child(id, 0xb7), .{ .x = center.x - bw / 2, .y = center.y + u.px(4), .w = bw, .h = u.px(30) }, name, .{ .selected = true });
}

test {
    @import("win32").refAllDeep(@This());
}
