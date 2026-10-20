//! Find in a terminal (the edit.find command): a bar on the top right of
//! the pane, matches on screen and in the history marked by the core,
//! "3 de 12", Enter for the next, Shift+Enter for the previous, Esc closes
//! (docs/spec/terminal.md).

const std = @import("std");
const gfx = @import("gfx");
const ui_mod = @import("ui");
const cadex = @import("cadex");
const Session = @import("session.zig").Session;

const Ui = ui_mod.Ui;

pub const Find = struct {
    open: bool = false,
    query: ui_mod.TextBuffer = .{},
    scroll: ui_mod.text_field.Scroll = .{},
    field: ui_mod.Id = ui_mod.id("terminal.find", 0),

    pub fn deinit(self: *Find, gpa: std.mem.Allocator) void {
        self.query.deinit(gpa);
    }

    pub fn show(self: *Find, ui: *Ui) void {
        self.open = true;
        self.query.selectAll();
        ui.focus = self.field;
    }

    /// `owner`: the pane, which gets the focus back when the bar closes.
    pub fn draw(self: *Find, ui: *Ui, session: *Session, area: gfx.Rect, owner: ui_mod.Id) void {
        const t = session.terminal;
        const bar: gfx.Rect = .{ .x = area.right() - ui.px(330), .y = area.y + ui.px(8), .w = ui.px(318), .h = ui.px(36) };
        ui.beginOverlay(bar);
        defer ui.endOverlay();
        ui.painter.fillRounded(bar.inset(-1, -1), ui.px(9), ui.style.panel_border);
        ui.painter.fillRounded(bar, ui.px(9), ui.style.panel);
        var row = bar.inset(ui.px(6), ui.px(5));
        var total: u32 = 0;
        var current: u32 = 0;
        _ = cadex.cadex_terminal_search_counts(t, &total, &current);
        var count_buf: [32]u8 = undefined;
        const count = if (self.query.text().len == 0) "" else if (total == 0) "nenhum" else std.fmt.bufPrint(&count_buf, "{d} de {d}", .{ current, total }) catch "";
        const close_rect = row.takeRight(ui.px(26));
        const count_rect = row.takeRight(ui.px(76));
        const result = ui_mod.text_field.textField(ui, self.field, row, &self.query, &self.scroll, .{ .placeholder = "Buscar", .framed = true });
        ui.painter.text(count, ui.style.small(), count_rect, ui.style.secondary_text, .{ .@"align" = .center });
        if (result.changed) _ = cadex.cadex_terminal_search_start(t, self.query.text().ptr, self.query.text().len);
        var found: bool = false;
        if (result.submitted) _ = cadex.cadex_terminal_search_select(t, if (ui.input.mods.shift) cadex.CADEX_SEARCH_PREVIOUS else cadex.CADEX_SEARCH_NEXT, &found);
        const x_id = ui_mod.id("terminal.find.close", 0);
        if (ui_mod.widgets.iconButton(ui, x_id, close_rect, @import("icons").phosphor.x, .{ .icon_size = 14 }) or result.cancelled) {
            self.open = false;
            cadex.cadex_terminal_search_stop(t);
            ui.focus = owner;
        }
    }
};

test {
    @import("win32").refAllDeep(@This());
}
